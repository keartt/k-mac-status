#include "Metrics.h"
#include <mach/mach.h>
#include <sys/sysctl.h>
#include <libproc.h>
#include <sys/resource.h>
#include <netinet/in.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/route.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

MemoryReading read_memory(void) {
    MemoryReading r = {0};
    vm_statistics64_data_t v; mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    mach_port_t host = mach_host_self();
    kern_return_t status = host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&v, &count);
    mach_port_deallocate(mach_task_self(), host);
    if (status != KERN_SUCCESS) return r;
    size_t size = sizeof(r.total);
    if (sysctlbyname("hw.memsize", &r.total, &size, NULL, 0) != 0) return r;
    // Purgeable pages are included in active/inactive; compressor uses physical pages only.
    uint64_t pages = (uint64_t)v.active_count + v.inactive_count + v.wire_count + v.compressor_page_count;
    uint64_t reclaimable = (uint64_t)v.purgeable_count + v.external_page_count;
    r.used = (pages > reclaimable ? pages - reclaimable : 0) * vm_kernel_page_size;
    r.compressed = (uint64_t)v.compressor_page_count * vm_kernel_page_size;
    struct xsw_usage swap = {0}; size = sizeof(swap);
    if (sysctlbyname("vm.swapusage", &swap, &size, NULL, 0) == 0) { r.swap = swap.xsu_used; r.swapValid = 1; }
    size = sizeof(r.pressure);
    sysctlbyname("kern.memorystatus_vm_pressure_level", &r.pressure, &size, NULL, 0);
    r.valid = r.total > 0 && r.used <= r.total;
    return r;
}
CPUReading read_cpu(void) {
    CPUReading r = {0}; host_cpu_load_info_data_t c;
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    mach_port_t host = mach_host_self();
    if (host_statistics(host, HOST_CPU_LOAD_INFO, (host_info_t)&c, &count) == KERN_SUCCESS) {
        r.user = c.cpu_ticks[CPU_STATE_USER]; r.system = c.cpu_ticks[CPU_STATE_SYSTEM];
        r.idle = c.cpu_ticks[CPU_STATE_IDLE]; r.nice = c.cpu_ticks[CPU_STATE_NICE]; r.valid = 1;
    }
    mach_port_deallocate(mach_task_self(), host);
    return r;
}
uint64_t own_footprint(void) {
    struct rusage_info_v2 usage = {0};
    return proc_pid_rusage(getpid(), RUSAGE_INFO_V2, (rusage_info_t *)&usage) == 0 ? usage.ri_phys_footprint : 0;
}
int process_capacity(void) { int n = proc_listallpids(NULL, 0); return n > 0 ? n + 128 : 128; }
int read_processes(ProcessReading *out, int capacity) {
    int bytes = proc_listallpids(NULL, 0);
    if (bytes <= 0) return -1;
    int count = bytes + 128; pid_t *pids = calloc(count, sizeof(pid_t));
    if (!pids) return -1;
    count = proc_listallpids(pids, count * sizeof(pid_t)); int used = 0;
    for (int i = 0; i < count && used < capacity; i++) {
        struct rusage_info_v2 usage = {0};
        if (pids[i] <= 0 || proc_pid_rusage(pids[i], RUSAGE_INFO_V2, (rusage_info_t *)&usage) != 0) continue;
        ProcessReading r = {0}; r.pid = pids[i]; r.bytes = usage.ri_phys_footprint;
        proc_pidpath(pids[i], r.path, sizeof(r.path));
        struct proc_bsdinfo bsd = {0};
        if (proc_pidinfo(pids[i], PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd)) == sizeof(bsd)) r.parent = bsd.pbi_ppid;
        out[used++] = r;
    }
    free(pids); return used;
}
NetworkReading read_network(void) {
    NetworkReading r = {0};
    // Use the IPv4 default route, then IPv6. Never sum bridge/VPN/physical counters together.
    unsigned int index = 0;
    for (int family = 0; family < 2 && !index; family++) {
        int mib[] = {CTL_NET, PF_ROUTE, 0, family ? AF_INET6 : AF_INET, NET_RT_DUMP2, 0};
        size_t size = 0;
        if (sysctl(mib, 6, NULL, &size, NULL, 0) != 0 || !size) continue;
        char *buffer = malloc(size); if (!buffer) continue;
        if (sysctl(mib, 6, buffer, &size, NULL, 0) == 0) {
            for (char *p = buffer; p + sizeof(struct rt_msghdr2) <= buffer + size;) {
                struct rt_msghdr2 *msg = (struct rt_msghdr2 *)p;
                if (msg->rtm_msglen < sizeof(*msg) + sizeof(struct sockaddr) || p + msg->rtm_msglen > buffer + size) break;
                struct sockaddr *dst = (struct sockaddr *)(msg + 1);
                if ((msg->rtm_flags & RTF_UP) && (msg->rtm_flags & RTF_GATEWAY) && !(msg->rtm_flags & RTF_HOST)) {
                    int zero = 1;
                    if (dst->sa_family == AF_INET) {
                        struct sockaddr_in *a = (struct sockaddr_in *)dst; zero = a->sin_addr.s_addr == 0;
                    } else if (dst->sa_family == AF_INET6) {
                        struct sockaddr_in6 *a = (struct sockaddr_in6 *)dst;
                        for (int j = 0; j < 16; j++) if (a->sin6_addr.s6_addr[j]) zero = 0;
                    } else zero = 0;
                    if (zero) { index = msg->rtm_index; break; }
                }
                p += msg->rtm_msglen;
            }
        }
        free(buffer);
    }
    if (!index || !if_indextoname(index, r.name)) return r;
    int mib[] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, (int)index};
    size_t size = 0;
    if (sysctl(mib, 6, NULL, &size, NULL, 0) != 0 || !size) return r;
    char *buffer = malloc(size); if (!buffer) return r;
    if (sysctl(mib, 6, buffer, &size, NULL, 0) == 0) {
        for (char *p = buffer; p + sizeof(struct rt_msghdr) <= buffer + size;) {
            struct rt_msghdr *header = (struct rt_msghdr *)p;
            if (!header->rtm_msglen || p + header->rtm_msglen > buffer + size) break;
            if (header->rtm_type == RTM_IFINFO2 && header->rtm_msglen >= sizeof(struct if_msghdr2)) {
                struct if_msghdr2 *msg = (struct if_msghdr2 *)p;
                if (msg->ifm_index == index) {
                    r.received = msg->ifm_data.ifi_ibytes; r.sent = msg->ifm_data.ifi_obytes; r.valid = 1; break;
                }
            }
            p += header->rtm_msglen;
        }
    }
    free(buffer); return r;
}

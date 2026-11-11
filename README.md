# k-mac-status

Apple Silicon용 초경량 macOS 메뉴 막대 모니터. 현재 검증 대상은 M4 / macOS 26.5.2입니다.

## 설치

`dist/k-mac-status.app`을 `/Applications`에 옮겨 실행하세요. 상태바의 도넛과 메모리 %를 누르면 상세 패널이 열립니다. 별도 런타임·설치 프로그램·상주 보조 도구는 없습니다. 종료는 패널 우측 상단의 전원 아이콘으로 합니다. 하단 버튼과 수동 새로고침은 없으며 패널이 열리면 자동 갱신합니다.

## 동작

- 패널 닫힘: 메모리만 5초 간격 수집.
- 패널 열림: CPU, GPU, 배터리 센서 온도, OS 열 상태, 디스크 여유, 기본 경로 인터페이스의 네트워크 속도를 2초 간격 수집.
- 실행 중인 일반 앱 중 메모리 사용량 상위 20개와 자기 자신 표시. 백그라운드 전용 앱·서비스는 제외하며 자기 자신은 순위와 별개로 항상 마지막에 표시합니다. 소속 `.app` 경로가 확인되는 헬퍼만 합산하며 접근이 제한된 프로세스·별도 실행 경로의 헬퍼는 빠질 수 있습니다.
- 앱 목록은 스크롤해서 모두 확인할 수 있습니다. 앱 footprint 합계와 전체 시스템 메모리는 서로 다른 집계입니다.
- 상세 지표는 2열 3행 카드로 배치합니다. 메모리·CPU·GPU는 큰 %가 있는 도넛과 작은 추이, 디스크는 용량 막대, 네트워크는 업로드·다운로드 각각의 면적 그래프로 표시합니다. 앱 이름 헤더·안내 문구·배터리 항목은 제거했습니다.
- 그래프는 열린 동안의 최대 30개 샘플만 메모리에 유지합니다. 패널을 닫으면 버립니다.
- 앱 자체의 디스크 캐시·로그·이력 저장·원격 통신 없음. 운영체제의 아이콘 캐시나 진단 기록은 OS가 관리합니다.
- 온도는 **배터리 센서** 값이며 CPU 온도가 아닙니다. 별도로 시스템 열 상태를 표시합니다.
- 디스크 여유는 macOS의 중요 작업용 사용 가능 공간(회수 가능 공간 포함)입니다.
- 네트워크는 기본 경로 인터페이스의 64비트 카운터 차이입니다. VPN 사용 시 해당 인터페이스 이름을 확인하세요. 인터넷 회선 최대 속도를 측정하는 기능은 아닙니다.
- 메모리 사용량은 `(active + inactive + wired + compressor - purgeable - external) × page size`로 계산합니다. 시스템 도구와 샘플링 시점·집계 방식에 따른 차이가 생길 수 있습니다.

## 경량성 실측

앱 번들 약 0.6MB. 최초 대기 footprint 약 16MB, 패널 사용 후에는 네이티브 UI 비용을 포함해 약 50MB 수준입니다. 패널 종료 시 사용자 정의 버퍼·아이콘 참조를 해제하고 자체 allocator의 반환 가능한 페이지를 OS에 돌려줍니다. AppKit과 OS가 관리하는 캐시까지 제거하지는 않습니다. 초기 30MB 목표는 패널 사용 후에는 충족하지 못했습니다.

지표 self-check, 밝은/어두운 렌더링, 8회 개폐 및 상세 수집 중지, ad-hoc 서명 검증을 수행했습니다. UI 제어 도구 연결 실패로 실제 자동 클릭은 검증하지 못했고, 잠자기 복귀·장시간 사용 영향은 미검증입니다.

## 빌드와 검사

Xcode 또는 macOS 26 SDK 및 Swift 컴파일러가 필요합니다. 외부 패키지는 없습니다.

```sh
./Scripts/build.sh
./dist/k-mac-status.app/Contents/MacOS/k-mac-status --self-test
./dist/k-mac-status.app/Contents/MacOS/k-mac-status --self-test --snapshot .build/panel-dark.png
./dist/k-mac-status.app/Contents/MacOS/k-mac-status --self-test --light --snapshot .build/panel-light.png
./dist/k-mac-status.app/Contents/MacOS/k-mac-status --lifecycle-test
```

수명주기 검사는 실제 상태바 패널을 여덟 번 열고 닫으며 상세 수집 중지와 뷰 해제를 확인한 뒤 종료합니다. 일반 실행에서는 검사 코드를 실행하지 않습니다.

빌드는 로컬 ad-hoc 서명을 사용합니다. Developer ID 서명·Apple 공증은 하지 않았으므로 다른 Mac에서는 Gatekeeper 확인이 필요할 수 있습니다. 최소 실행 버전은 macOS 26.0이며 이전 버전과 Intel은 지원하지 않습니다.

## 아이콘

[Lucide memory-stick](https://github.com/lucide-icons/lucide/blob/main/icons/memory-stick.svg)을 단색 배경 위에 배치했습니다. 원본 SVG와 라이선스는 `Assets`에, 배포용 라이선스는 앱 Resources에 포함했습니다. 아이콘 재생성:

```sh
swift Scripts/icon.swift
iconutil -c icns .build/AppIcon.iconset -o Assets/AppIcon.icns
```

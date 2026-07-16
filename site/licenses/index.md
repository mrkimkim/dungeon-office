---
layout: page
title: 오픈소스 라이선스
permalink: /licenses/
---

# 던전 오피스 오픈소스 라이선스

이 문서와 아래 두 전문은 공개 웹페이지와 앱 내부 `정보·법적 고지` 화면이 함께 사용하는 오픈소스 고지 원문 묶음입니다. 앱은 세 Markdown 원문을 하나로 이어 붙여 네트워크 없이 표시합니다.

- [Godot Engine 4.7 저작권·제3자 고지](https://mrkimkim.github.io/dungeon-office/licenses/godot-copyright/)
- [Android 런타임 오픈소스 고지](https://mrkimkim.github.io/dungeon-office/licenses/android-runtime/)

## Godot Engine

- 프로젝트: Godot Engine
- 웹사이트: <https://godotengine.org/>
- 저작권: Copyright (c) 2014-present Godot Engine contributors. Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.
- 라이선스: MIT License

```text
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Godot 배포 바이너리에 포함된 제3자 구성요소의 저작권자와 라이선스 전문은 Godot `4.7-stable`의 공식 [`COPYRIGHT.txt`](https://mrkimkim.github.io/dungeon-office/licenses/godot-copyright/) 원문에서 확인할 수 있습니다.

## Android 런타임

Godot 4.7 Android 템플릿이 배포 앱에 포함하는 Kotlin, kotlinx.coroutines, AndroidX, JetBrains Annotations, Guava ListenableFuture와 JSpecify 구성요소는 Apache License 2.0을 따릅니다. 해석된 실제 모듈·버전 목록과 Apache License 2.0 전문은 [Android 런타임 오픈소스 고지](https://mrkimkim.github.io/dungeon-office/licenses/android-runtime/)에서 확인할 수 있습니다.

## 출시 후보의 고지 검증

현재 묶음은 Godot 4.7 공식 Android 템플릿과 그 템플릿이 해석한 런타임 의존성을 기준으로 합니다. 새로운 런타임 라이브러리, 폰트 또는 에셋을 추가할 때에는 배포 권한과 필요한 고지 문구를 확인하고, 해당 구성요소를 포함한 빌드를 배포하기 전에 세 원문을 갱신해야 합니다. Android 운영체제 구성요소처럼 앱에 재배포하지 않는 외부 소프트웨어는 이 목록에 포함하지 않습니다.

마지막 갱신일: 2026-07-14

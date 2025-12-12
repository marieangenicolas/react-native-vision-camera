<a href="https://margelo.com">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="./docs/static/img/banner-dark.png" />
    <source media="(prefers-color-scheme: light)" srcset="./docs/static/img/banner-light.png" />
    <img alt="VisionCamera" src="./docs/static/img/banner-light.png" />
  </picture>
</a>

<br />

<div>
  <img align="right" width="35%" src="docs/static/img/example.png">
</div>

# @marieangenicolas/react-native-vision-camera-filtered-preview

Custom fork of [react-native-vision-camera](https://github.com/mrousavy/react-native-vision-camera) with additional features and fixes, including support for real-time LUT-based filtering in the camera preview.

### Features

VisionCamera is a powerful, high-performance Camera library for React Native. It features:

- 📸 Photo and Video capture
- 👁️ QR/Barcode scanner
- 📱 Customizable devices and multi-cameras ("fish-eye" zoom)
- 🎞️ Customizable resolutions and aspect-ratios (4k/8k images)
- ⏱️ Customizable FPS (30..240 FPS)
- 🧩 [Frame Processors](https://react-native-vision-camera.com/docs/guides/frame-processors) (JS worklets to run facial recognition, AI object detection, realtime video chats, ...)
- 🎨 Drawing shapes, text, filters or shaders onto the Camera
- 🔍 Smooth zooming (Reanimated)
- ⏯️ Fast pause and resume
- 🌓 HDR & Night modes
- ⚡ Custom C++/GPU accelerated video pipeline (OpenGL)

Install VisionCamera from npm:

```sh
npm i react-native-vision-camera
cd ios && pod install
```

..and get started by [setting up permissions](https://react-native-vision-camera.com/docs/guides)!

### Documentation

- [Guides](https://react-native-vision-camera.com/docs/guides)
- [API](https://react-native-vision-camera.com/docs/api)
- [Example](./example/)
- [Frame Processor Plugins](https://react-native-vision-camera.com/docs/guides/frame-processor-plugins-community)

### ShadowLens

To see VisionCamera in action, check out [ShadowLens](https://mrousavy.com/projects/shadowlens)!

<div>
  <a href="https://apps.apple.com/app/shadowlens/id6471849004">
    <img height="40" src="docs/static/img/appstore.svg" />
  </a>
  <a href="https://play.google.com/store/apps/details?id=com.mrousavy.shadowlens">
    <img height="40" src="docs/static/img/googleplay.svg" />
  </a>
</div>

### Example

```tsx
function App() {
  const device = useCameraDevice('back')

  if (device == null) return <NoCameraErrorView />
  return <Camera style={StyleSheet.absoluteFill} device={device} isActive={true} />
}
```

> See the [example](./example/) app

## Changes from Original

- Added support for applying a LUT (Lookup Table) filter to the live camera preview.
- New `lutAsset` prop that enables real-time preview filtering.
- By default, no LUT is applied (`lutAsset` is undefined).
- When using `lutAsset`, the camera must be configured with:
  - `video={true}`
  - `pixelFormat="rgb"`

## Usage

You can optionally pass a LUT image to apply a real-time filter to the camera preview. If `lutAsset` is not provided, the preview remains unfiltered.

### Example

```jsx
import { Camera } from '@your-username/react-native-vision-camera'
import { Image } from 'react-native'

const lutAsset = require('../assets/lut.png')

;<Camera style={{ flex: 1 }} video={true} pixelFormat="rgb" lutAsset={Image.resolveAssetSource(lutAsset)} />
```

## Notes

- `lutAsset` must be passed using `Image.resolveAssetSource(...)`.
- The camera preview will apply the LUT filter in real time.
- If `lutAsset` is omitted, the preview stays unchanged.

## Official Documentation

All other functionality is identical to the original library. Refer to the official documentation here: https://react-native-vision-camera.com/

### Adopting at scale

<a href="https://github.com/sponsors/mrousavy">
  <img align="right" width="160" alt="This library helped you? Consider sponsoring!" src=".github/funding-octocat.svg">
</a>

VisionCamera is provided _as is_, I work on it in my free time.

If you're integrating VisionCamera in a production app, consider [funding this project](https://github.com/sponsors/mrousavy) and <a href="mailto:me@mrousavy.com?subject=Adopting VisionCamera at scale">contact me</a> to receive premium enterprise support, help with issues, prioritize bugfixes, request features, help at integrating VisionCamera and/or Frame Processors, and more.

### Socials

- 🐦 [**Follow me on Twitter**](https://twitter.com/mrousavy) for updates
- 📝 [**Check out my blog**](https://mrousavy.com/blog) for examples and experiments
- 💬 [**Join the Margelo Community Discord**](https://margelo.com/discord) for chatting about VisionCamera
- 💖 [**Sponsor me on GitHub**](https://github.com/sponsors/mrousavy) to support my work
- 🍪 [**Buy me a Ko-Fi**](https://ko-fi.com/mrousavy) to support my work

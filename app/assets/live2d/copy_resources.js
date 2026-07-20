const fs = require('fs');
const path = require('path');

const sdkPath = path.resolve(__dirname, 'CubismSdkForWeb-5-r.5');

const resources = [
  { src: path.join(sdkPath, 'Core'), dst: './dist/Core' },
  { src: path.join(sdkPath, 'Framework/Shaders'), dst: './dist/Framework/Shaders' },
];

resources.forEach(({ src, dst }) => {
  if (fs.existsSync(dst)) {
    fs.rmSync(dst, { recursive: true });
  }
  fs.cpSync(src, dst, { recursive: true });
});

console.log('[copy_resources] done');

const fs = require('fs');
const path = require('path');

const dirs = [
  'dist',
  'dist/Core',
  'dist/assets',
  'dist/Framework',
  'dist/Framework/Shaders',
  'dist/Framework/Shaders/WebGL',
];

const gitignoreContent = '*\n!*/\n!.gitignore\n!.gitkeep\n';

dirs.forEach((d) => {
  const dirPath = path.resolve(__dirname, d);
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
  }
});

fs.writeFileSync(path.resolve(__dirname, 'dist/.gitignore'), gitignoreContent);

dirs.forEach((d) => {
  fs.writeFileSync(path.resolve(__dirname, d, '.gitkeep'), '');
});

console.log('[restore_placeholders] done');

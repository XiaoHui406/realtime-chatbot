import { CubismFramework, Option } from '@framework/live2dcubismframework';
import * as LAppDefine from './lappdefine';
import { LAppPal } from './lapppal';
import { LAppGlManager } from './lappglmanager';
import { Live2DModel } from './model';
import { CubismMatrix44 } from '@framework/math/cubismmatrix44';
import './bridge';

let s_instance: Live2DApp | null = null;

export class Live2DApp {
  public static getInstance(): Live2DApp {
    if (s_instance == null) {
      s_instance = new Live2DApp();
    }
    return s_instance;
  }

  private _canvas: HTMLCanvasElement | null = null;
  private _glManager: LAppGlManager | null = null;
  private _model: Live2DModel | null = null;
  private _cubismOption: Option | null = null;
  private _animFrameId: number = 0;

  public get ready(): boolean {
    return this._model?.ready ?? false;
  }

  public get model(): Live2DModel | null {
    return this._model;
  }

  public initialize(): boolean {
    this._cubismOption = new Option();
    this._cubismOption.logFunction = LAppPal.printMessage;
    this._cubismOption.loggingLevel = LAppDefine.CubismLoggingLevel;
    CubismFramework.startUp(this._cubismOption);
    CubismFramework.initialize();

    this._canvas = document.createElement('canvas');
    this._canvas.style.width = '100%';
    this._canvas.style.height = '100%';
    document.body.appendChild(this._canvas);

    this._glManager = new LAppGlManager();
    if (!this._glManager.initialize(this._canvas)) {
      return false;
    }

    this.resizeCanvas();

    const gl = this._glManager.getGl()!;
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    this._model = new Live2DModel();
    this._model.initialize(this._canvas, this._glManager);

    return true;
  }

  public resizeCanvas(): void {
    if (!this._canvas) return;
    const dpr = window.devicePixelRatio || 1;
    this._canvas.width = this._canvas.clientWidth * dpr;
    this._canvas.height = this._canvas.clientHeight * dpr;
    const gl = this._glManager?.getGl();
    if (gl) {
      gl.viewport(0, 0, gl.drawingBufferWidth, gl.drawingBufferHeight);
    }
  }

  public run(): void {
    const loop = (): void => {
      if (s_instance == null) return;

      LAppPal.updateTime();

      const gl = this._glManager!.getGl()!;
      gl.clearColor(0.0, 0.0, 0.0, 1.0);
      gl.enable(gl.DEPTH_TEST);
      gl.depthFunc(gl.LEQUAL);
      gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
      gl.clearDepth(1.0);
      gl.enable(gl.BLEND);
      gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

      if (this._model) {
        const { width, height } = this._canvas!;
        const projection = new CubismMatrix44();

        if (this._model.getModel()) {
          if (this._model.getModel()!.getCanvasWidth() > 1.0 && width < height) {
            this._model.getModelMatrix().setWidth(2.0);
            projection.scale(1.0, width / height);
          } else {
            projection.scale(height / width, 1.0);
          }
        }

        this._model.update();
        this._model.draw(projection);
      }

      gl.flush();
      this._animFrameId = requestAnimationFrame(loop);
    };
    loop();
  }

  public async switchModel(dirPath: string): Promise<boolean> {
    if (!this._model) return false;
    return this._model.loadAssets(dirPath);
  }

  public release(): void {
    cancelAnimationFrame(this._animFrameId);
    if (this._model) {
      this._model.release();
      this._model = null;
    }
    CubismFramework.dispose();
    this._cubismOption = null;
    s_instance = null;
  }
}

document.addEventListener('DOMContentLoaded', () => {
  const app = Live2DApp.getInstance();
  if (!app.initialize()) {
    const el = document.getElementById('l2d-status');
    if (el) el.textContent = 'WebGL2 not supported';
    return;
  }
  app.run();
});

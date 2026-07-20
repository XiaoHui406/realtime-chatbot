export class LAppGlManager {
  private _gl: WebGL2RenderingContext | null = null;

  public initialize(canvas: HTMLCanvasElement): boolean {
    this._gl = canvas.getContext('webgl2');
    if (!this._gl) {
      console.error('[LAppGlManager] Cannot initialize WebGL2');
      return false;
    }
    return true;
  }

  public release(): void {}

  public getGl(): WebGL2RenderingContext | null {
    return this._gl;
  }
}

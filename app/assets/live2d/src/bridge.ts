import { Live2DApp } from './main';

(window as any).Live2DBridge = {
  isReady(): boolean {
    return Live2DApp.getInstance().ready;
  },

  setMouthOpen(v: number): void {
    Live2DApp.getInstance().model?.setMouthOpen(v);
  },

  setEyeOpen(v: number): void {
    Live2DApp.getInstance().model?.setEyeOpen(v);
  },

  setExpression(name: string): void {
    Live2DApp.getInstance().model?.setExpression(name);
  },

  startMotion(group: string, index: number): void {
    Live2DApp.getInstance().model?.startMotion(group, index);
  },

  async switchModel(path: string): Promise<boolean> {
    return await Live2DApp.getInstance().switchModel(path);
  },

  getExpressionNames(): string[] {
    return Live2DApp.getInstance().model?.getExpressionNames() ?? [];
  },

  getMotionGroups(): Array<{ name: string; count: number }> {
    return Live2DApp.getInstance().model?.getMotionGroups() ?? [];
  },
};

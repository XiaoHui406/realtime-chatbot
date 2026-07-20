import { CubismDefaultParameterId } from '@framework/cubismdefaultparameterid';
import { CubismModelSettingJson } from '@framework/cubismmodelsettingjson';
import { CubismEyeBlink } from '@framework/effect/cubismeyeblink';
import { CubismBreath, BreathParameterData } from '@framework/effect/cubismbreath';
import { CubismLook, LookParameterData } from '@framework/effect/cubismlook';
import { ICubismModelSetting } from '@framework/icubismmodelsetting';
import { CubismIdHandle } from '@framework/id/cubismid';
import { CubismFramework } from '@framework/live2dcubismframework';
import { CubismMatrix44 } from '@framework/math/cubismmatrix44';
import { CubismUserModel } from '@framework/model/cubismusermodel';
import { ACubismMotion } from '@framework/motion/acubismmotion';
import { CubismMotion } from '@framework/motion/cubismmotion';
import { CubismExpressionMotion } from '@framework/motion/cubismexpressionmotion';
import { CubismMotionQueueEntryHandle, InvalidMotionQueueEntryHandleValue } from '@framework/motion/cubismmotionqueuemanager';
import { CubismUpdateScheduler } from '@framework/motion/cubismupdatescheduler';
import { CubismEyeBlinkUpdater } from '@framework/motion/cubismeyeblinkupdater';
import { CubismBreathUpdater } from '@framework/motion/cubismbreathupdater';
import { CubismExpressionUpdater } from '@framework/motion/cubismexpressionupdater';
import { CubismPhysicsUpdater } from '@framework/motion/cubismphysicsupdater';
import { CubismPoseUpdater } from '@framework/motion/cubismposeupdater';
import { CubismLookUpdater } from '@framework/motion/cubismlookupdater';

import * as LAppDefine from './lappdefine';
import { LAppPal } from './lapppal';
import { LAppGlManager } from './lappglmanager';

enum LoadStep {
  LoadAssets,
  LoadModel,
  WaitLoadModel,
  LoadExpression,
  WaitLoadExpression,
  LoadPhysics,
  WaitLoadPhysics,
  LoadPose,
  WaitLoadPose,
  SetupEyeBlink,
  SetupBreath,
  SetupLook,
  LoadMotion,
  WaitLoadMotion,
  LoadTexture,
  WaitLoadTexture,
  CompleteSetup,
}

export class Live2DModel extends CubismUserModel {
  private _modelSetting: ICubismModelSetting | null = null;
  private _modelHomeDir: string = '';
  private _state: LoadStep = LoadStep.LoadAssets;
  private _updateScheduler: CubismUpdateScheduler;
  private _motionUpdated: boolean = false;

  private _eyeBlinkIds: Array<CubismIdHandle> = [];
  private _lipSyncIds: Array<CubismIdHandle> = [];

  private _motions: Map<string, ACubismMotion> = new Map();
  private _expressions: Map<string, ACubismMotion> = new Map();

  private _expressionCount: number = 0;
  private _textureCount: number = 0;
  private _motionCount: number = 0;
  private _allMotionCount: number = 0;

  private _idParamAngleX: CubismIdHandle;
  private _idParamAngleY: CubismIdHandle;
  private _idParamAngleZ: CubismIdHandle;
  private _idParamBodyAngleX: CubismIdHandle;

  private _idMouthOpenY: CubismIdHandle;
  private _idEyeLOpen: CubismIdHandle;
  private _idEyeROpen: CubismIdHandle;

  private _look: CubismLook | null = null;

  private _canvas: HTMLCanvasElement | null = null;
  private _glManager: LAppGlManager | null = null;
  private _textures: Map<number, WebGLTexture> = new Map();

  private _manualMouthOpen: number = 0;
  private _manualEyeOpen: number = 1.0;

  public ready: boolean = false;
  public error: string | null = null;

  constructor() {
    super();
    this._updateScheduler = new CubismUpdateScheduler();

    this._idParamAngleX = CubismFramework.getIdManager().getId(CubismDefaultParameterId.ParamAngleX);
    this._idParamAngleY = CubismFramework.getIdManager().getId(CubismDefaultParameterId.ParamAngleY);
    this._idParamAngleZ = CubismFramework.getIdManager().getId(CubismDefaultParameterId.ParamAngleZ);
    this._idParamBodyAngleX = CubismFramework.getIdManager().getId(CubismDefaultParameterId.ParamBodyAngleX);
    this._idMouthOpenY = CubismFramework.getIdManager().getId(CubismDefaultParameterId.ParamMouthOpenY);
    this._idEyeLOpen = CubismFramework.getIdManager().getId(CubismDefaultParameterId.ParamEyeLOpen);
    this._idEyeROpen = CubismFramework.getIdManager().getId(CubismDefaultParameterId.ParamEyeROpen);
  }

  public initialize(canvas: HTMLCanvasElement, glManager: LAppGlManager): void {
    this._canvas = canvas;
    this._glManager = glManager;
  }

  public async loadAssets(dirPath: string): Promise<boolean> {
    this.releaseModel();
    this.ready = false;
    this.error = null;
    this._modelHomeDir = dirPath;

    try {
      const dirName = dirPath.split('/').filter((s) => s.length > 0).pop() || 'model';
      const model3JsonPath = `${dirPath}${dirName}.model3.json`;

      console.log(`[Live2DModel] Loading model from ${model3JsonPath}`);
      const resp = await fetch(model3JsonPath);
      if (!resp.ok) {
        throw new Error(`Failed to fetch ${model3JsonPath}: ${resp.status}`);
      }
      const arrayBuffer = await resp.arrayBuffer();

      this._modelSetting = new CubismModelSettingJson(arrayBuffer, arrayBuffer.byteLength);
      this._state = LoadStep.LoadModel;

      await this.setupModel(this._modelSetting);

      document.getElementById('l2d-status')!.style.display = 'none';
      return true;
    } catch (e: any) {
      this.error = e.message;
      console.error('[Live2DModel] Load failed:', e);
      return false;
    }
  }

  private async setupModel(setting: ICubismModelSetting): Promise<void> {
    await this.loadModelData(setting);
    await this.loadExpressions(setting);
    await this.loadModelPhysics(setting);
    await this.loadModelPose(setting);
    this.setupEyeBlink(setting);
    this.setupBreath();
    this.setupEyeBlinkIds(setting);
    this.setupLipSyncIds(setting);
    this.setupLook();

    this._updateScheduler.sortUpdatableList();

    const layout: Map<string, number> = new Map();
    setting.getLayoutMap(layout);
    this._modelMatrix.setupFromLayout(layout);

    await this.loadMotions(setting);

    this._state = LoadStep.LoadTexture;

    this._motionManager.stopAllMotions();
    this._updating = false;
    this._initialized = true;

    this.createRenderer(this._canvas!.width, this._canvas!.height);
    this.getRenderer().startUp(this._glManager!.getGl()!);
    this.getRenderer().loadShaders(LAppDefine.ShaderPath);

    await this.loadTextures(setting);

    this._state = LoadStep.CompleteSetup;
    this.ready = true;
    console.log('[Live2DModel] Model loaded successfully');
  }

  private async loadModelData(setting: ICubismModelSetting): Promise<void> {
    const modelFileName = setting.getModelFileName();
    if (!modelFileName) {
      throw new Error('Model file name not found in setting');
    }

    const resp = await fetch(`${this._modelHomeDir}${modelFileName}`);
    if (!resp.ok) {
      throw new Error(`Failed to fetch ${modelFileName}: ${resp.status}`);
    }
    const buffer = await resp.arrayBuffer();
    this.loadModel(buffer, LAppDefine.MOCConsistencyValidationEnable);
  }

  private async loadExpressions(setting: ICubismModelSetting): Promise<void> {
    const count = setting.getExpressionCount();
    if (count === 0) return;

    for (let i = 0; i < count; i++) {
      const name = setting.getExpressionName(i);
      const file = setting.getExpressionFileName(i);
      try {
        const resp = await fetch(`${this._modelHomeDir}${file}`);
        const buffer = await resp.arrayBuffer();
        const motion: ACubismMotion = this.loadExpression(buffer, buffer.byteLength, name);
        this._expressions.set(name, motion);
        this._expressionCount++;
      } catch (e) {
        console.warn(`[Live2DModel] Failed to load expression ${name}:`, e);
      }
    }

    if (this._expressionManager) {
      const updater = new CubismExpressionUpdater(this._expressionManager);
      this._updateScheduler.addUpdatableList(updater);
    }
  }

  private async loadModelPhysics(setting: ICubismModelSetting): Promise<void> {
    const fileName = setting.getPhysicsFileName();
    if (!fileName) return;

    try {
      const resp = await fetch(`${this._modelHomeDir}${fileName}`);
      const buffer = await resp.arrayBuffer();
      this.loadPhysics(buffer, buffer.byteLength);

      if (this._physics) {
        const updater = new CubismPhysicsUpdater(this._physics);
        this._updateScheduler.addUpdatableList(updater);
      }
    } catch (e) {
      console.warn('[Live2DModel] Failed to load physics:', e);
    }
  }

  private async loadModelPose(setting: ICubismModelSetting): Promise<void> {
    const fileName = setting.getPoseFileName();
    if (!fileName) return;

    try {
      const resp = await fetch(`${this._modelHomeDir}${fileName}`);
      const buffer = await resp.arrayBuffer();
      this.loadPose(buffer, buffer.byteLength);

      if (this._pose) {
        const updater = new CubismPoseUpdater(this._pose);
        this._updateScheduler.addUpdatableList(updater);
      }
    } catch (e) {
      console.warn('[Live2DModel] Failed to load pose:', e);
    }
  }

  private setupEyeBlink(setting: ICubismModelSetting): void {
    if (setting.getEyeBlinkParameterCount() > 0) {
      this._eyeBlink = CubismEyeBlink.create(setting);
      const updater = new CubismEyeBlinkUpdater(() => this._motionUpdated, this._eyeBlink);
      this._updateScheduler.addUpdatableList(updater);
    }
  }

  private setupBreath(): void {
    this._breath = CubismBreath.create();
    const params: Array<BreathParameterData> = [
      new BreathParameterData(this._idParamAngleX, 0.0, 15.0, 6.5345, 0.5),
      new BreathParameterData(this._idParamAngleY, 0.0, 8.0, 3.5345, 0.5),
      new BreathParameterData(this._idParamAngleZ, 0.0, 10.0, 5.5345, 0.5),
      new BreathParameterData(this._idParamBodyAngleX, 0.0, 4.0, 15.5345, 0.5),
      new BreathParameterData(
        CubismFramework.getIdManager().getId(CubismDefaultParameterId.ParamBreath),
        0.5, 0.5, 3.2345, 1
      ),
    ];
    this._breath.setParameters(params);

    const updater = new CubismBreathUpdater(this._breath);
    this._updateScheduler.addUpdatableList(updater);
  }

  private setupEyeBlinkIds(setting: ICubismModelSetting): void {
    const count = setting.getEyeBlinkParameterCount();
    this._eyeBlinkIds = [];
    for (let i = 0; i < count; i++) {
      this._eyeBlinkIds.push(setting.getEyeBlinkParameterId(i));
    }
  }

  private setupLipSyncIds(setting: ICubismModelSetting): void {
    const count = setting.getLipSyncParameterCount();
    this._lipSyncIds = [];
    for (let i = 0; i < count; i++) {
      this._lipSyncIds.push(setting.getLipSyncParameterId(i));
    }
  }

  private setupLook(): void {
    this._look = CubismLook.create();
    const params: Array<LookParameterData> = [
      new LookParameterData(this._idParamAngleX, 30.0, 0.0, 0.0),
      new LookParameterData(this._idParamAngleY, 0.0, 30.0, 0.0),
      new LookParameterData(this._idParamAngleZ, 0.0, 0.0, -30.0),
      new LookParameterData(this._idParamBodyAngleX, 10.0, 0.0, 0.0),
      new LookParameterData(
        CubismFramework.getIdManager().getId(CubismDefaultParameterId.ParamEyeBallX),
        1.0, 0.0, 0.0
      ),
      new LookParameterData(
        CubismFramework.getIdManager().getId(CubismDefaultParameterId.ParamEyeBallY),
        0.0, 1.0, 0.0
      ),
    ];
    this._look.setParameters(params);

    const updater = new CubismLookUpdater(this._look, this._dragManager);
    this._updateScheduler.addUpdatableList(updater);
  }

  private async loadMotions(setting: ICubismModelSetting): Promise<void> {
    const groupCount = setting.getMotionGroupCount();
    if (groupCount === 0) return;

    const group: string[] = [];
    for (let i = 0; i < groupCount; i++) {
      group[i] = setting.getMotionGroupName(i);
      this._allMotionCount += setting.getMotionCount(group[i]);
    }

    for (let i = 0; i < groupCount; i++) {
      await this.preLoadMotionGroup(setting, group[i]);
    }
  }

  private async preLoadMotionGroup(setting: ICubismModelSetting, group: string): Promise<void> {
    const count = setting.getMotionCount(group);
    for (let i = 0; i < count; i++) {
      const fileName = setting.getMotionFileName(group, i);
      const name = `${group}_${i}`;

      try {
        const resp = await fetch(`${this._modelHomeDir}${fileName}`);
        const buffer = await resp.arrayBuffer();
        const motion: CubismMotion = this.loadMotion(
          buffer, buffer.byteLength, name,
          null, null,
          setting, group, i,
          LAppDefine.MotionConsistencyValidationEnable
        );

        if (motion) {
          motion.setEffectIds(this._eyeBlinkIds, this._lipSyncIds);
          this._motions.set(name, motion);
          this._motionCount++;
        }
      } catch (e) {
        console.warn(`[Live2DModel] Failed to load motion ${group}_${i}:`, e);
      }
    }
  }

  private async loadTextures(setting: ICubismModelSetting): Promise<void> {
    const textureCount = setting.getTextureCount();
    const usePremultiply = true;

    for (let i = 0; i < textureCount; i++) {
      const fileName = setting.getTextureFileName(i);
      if (!fileName) continue;

      const texturePath = `${this._modelHomeDir}${fileName}`;
      try {
        const textureId = await this.createTexture(texturePath, usePremultiply);
        this.getRenderer().bindTexture(i, textureId);
        this._textureCount++;
      } catch (e) {
        console.warn(`[Live2DModel] Failed to load texture ${fileName}:`, e);
      }
    }

    this.getRenderer().setIsPremultipliedAlpha(usePremultiply);
  }

  private async createTexture(path: string, usePremultiply: boolean): Promise<WebGLTexture> {
    const gl = this._glManager!.getGl()!;
    const img = await this.loadImage(path);

    const texture = gl.createTexture()!;
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, usePremultiply ? 1 : 0);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, img);
    gl.generateMipmap(gl.TEXTURE_2D);

    gl.bindTexture(gl.TEXTURE_2D, null);
    return texture;
  }

  private loadImage(path: string): Promise<HTMLImageElement> {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () => reject(new Error(`Failed to load image: ${path}`));
      img.src = path;
    });
  }

  public update(): void {
    if (this._state !== LoadStep.CompleteSetup) return;
    if (!this._model) return;

    const deltaTimeSeconds = LAppPal.getDeltaTime();

    this._model.loadParameters();
    this._motionUpdated = false;

    if (this._motionManager.isFinished()) {
      this.startRandomMotion(LAppDefine.MotionGroupIdle, LAppDefine.PriorityIdle);
    } else {
      this._motionUpdated = this._motionManager.updateMotion(this._model, deltaTimeSeconds);
    }

    this._model.saveParameters();

    this._updateScheduler.onLateUpdate(this._model, deltaTimeSeconds);

    this.applyManualParameters();

    this._model.update();
  }

  private applyManualParameters(): void {
    if (!this._model) return;

    if (this._model.getParameterIndex(this._idMouthOpenY) !== -1) {
      this._model.setParameterValueByIndex(
        this._model.getParameterIndex(this._idMouthOpenY),
        this._manualMouthOpen
      );
    }

    for (const id of this._lipSyncIds) {
      if (this._model.getParameterIndex(id) !== -1) {
        this._model.setParameterValueByIndex(
          this._model.getParameterIndex(id),
          this._manualMouthOpen
        );
      }
    }

    const eyeVal = this._manualEyeOpen;
    if (this._model.getParameterIndex(this._idEyeLOpen) !== -1) {
      const idx = this._model.getParameterIndex(this._idEyeLOpen);
      const current = this._model.getParameterValueByIndex(idx);
      this._model.setParameterValueByIndex(idx, current * eyeVal);
    }
    if (this._model.getParameterIndex(this._idEyeROpen) !== -1) {
      const idx = this._model.getParameterIndex(this._idEyeROpen);
      const current = this._model.getParameterValueByIndex(idx);
      this._model.setParameterValueByIndex(idx, current * eyeVal);
    }
  }

  public draw(matrix: CubismMatrix44): void {
    if (!this._model) return;
    if (this._state !== LoadStep.CompleteSetup) return;

    matrix.multiplyByMatrix(this._modelMatrix);

    const canvas = this._canvas!;
    const viewport: number[] = [0, 0, canvas.width, canvas.height];
    this.getRenderer().setRenderState(this._glManager!.getGl()!.getParameter(this._glManager!.getGl()!.FRAMEBUFFER_BINDING), viewport);
    this.getRenderer().setMvpMatrix(matrix);
    this.getRenderer().drawModel(LAppDefine.ShaderPath);
  }

  public setMouthOpen(v: number): void {
    this._manualMouthOpen = Math.max(0, Math.min(1, v));
  }

  public setEyeOpen(v: number): void {
    this._manualEyeOpen = Math.max(0, Math.min(1, v));
  }

  public setExpression(expressionId: string): void {
    const motion = this._expressions.get(expressionId);
    if (motion) {
      this._expressionManager?.startMotion(motion, false);
    } else {
      console.warn(`[Live2DModel] Expression "${expressionId}" not found. Available: ${Array.from(this._expressions.keys()).join(', ')}`);
    }
  }

  public startMotion(group: string, no: number, priority: number = LAppDefine.PriorityForce): CubismMotionQueueEntryHandle {
    if (!this._modelSetting) return InvalidMotionQueueEntryHandleValue;

    const name = `${group}_${no}`;
    const motion = this._motions.get(name) as CubismMotion;
    if (motion) {
      return this._motionManager.startMotionPriority(motion, false, priority);
    }

    console.warn(`[Live2DModel] Motion "${name}" not found`);
    return InvalidMotionQueueEntryHandleValue;
  }

  public startRandomMotion(group: string, priority: number): CubismMotionQueueEntryHandle {
    if (!this._modelSetting) return InvalidMotionQueueEntryHandleValue;
    const count = this._modelSetting.getMotionCount(group);
    if (count === 0) return InvalidMotionQueueEntryHandleValue;

    const no = Math.floor(Math.random() * count);
    return this.startMotion(group, no, priority);
  }

  public getExpressionNames(): string[] {
    return Array.from(this._expressions.keys());
  }

  public getMotionGroups(): Array<{ name: string; count: number }> {
    if (!this._modelSetting) return [];
    const groups: Array<{ name: string; count: number }> = [];
    const groupCount = this._modelSetting.getMotionGroupCount();
    for (let i = 0; i < groupCount; i++) {
      const name = this._modelSetting.getMotionGroupName(i);
      groups.push({ name, count: this._modelSetting.getMotionCount(name) });
    }
    return groups;
  }

  public releaseModel(): void {
    this.ready = false;
    this._state = LoadStep.LoadAssets;
    this._motions.clear();
    this._expressions.clear();
    this._eyeBlinkIds = [];
    this._lipSyncIds = [];
    this._modelSetting = null;
    this._modelHomeDir = '';
    this._expressionCount = 0;
    this._textureCount = 0;
    this._motionCount = 0;
    this._allMotionCount = 0;
    this._manualMouthOpen = 0;
    this._manualEyeOpen = 1.0;

    if (this._eyeBlink) {
      CubismEyeBlink.delete(this._eyeBlink);
    }
    if (this._breath) {
      CubismBreath.delete(this._breath);
    }
    if (this._look) {
      CubismLook.delete(this._look);
      this._look = null;
    }
    if (this._updateScheduler) {
      this._updateScheduler.release();
      this._updateScheduler = new CubismUpdateScheduler();
    }
    if (this._motionManager) {
      this._motionManager.stopAllMotions();
    }
  }

  public release(): void {
    this.releaseModel();
    super.release();
  }
}

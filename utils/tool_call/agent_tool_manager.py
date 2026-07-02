"""
Function calling 工具管理器：封装工具注册、schema 生成、调用与自动加载。

MIT License

Copyright (c) 2025 XiaoHui406

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
"""

import asyncio
import importlib
import os
from pydantic import BaseModel, Field, create_model
from typing import Callable, Type, get_type_hints, Optional
import inspect
from openai.types.chat import (
    ChatCompletionMessageFunctionToolCallParam,
    ChatCompletionFunctionToolParam,
    ChatCompletionToolMessageParam,
)
from openai.types.shared_params import FunctionDefinition
import json
import logging


class AgentTool(BaseModel):
    """
    func: 加入function_calling的函数
    InputClass: 用于生成JSON Schema的Pydantic模型类
    """

    func: Callable
    InputClass: Type[BaseModel]

    def to_tool(self) -> ChatCompletionFunctionToolParam:
        name = self.func.__name__
        description = (
            self.func.__doc__.strip()
            if self.func.__doc__
            else f"{self.func.__name__} tool"
        )
        parameters = self.InputClass.model_json_schema()

        return ChatCompletionFunctionToolParam(
            type="function",
            function=FunctionDefinition(
                name=name, description=description, parameters=parameters
            ),
        )


class AgentToolManager:
    """
    工具管理器：提供工具注册、schema 生成、工具调用和自动加载。
    - agent_tool: 将函数注册为工具，保持原函数可调用
    - generate_tools: 生成 OpenAI tools 所需的 JSON Schema
    - call_tool: 解析 tool_calls，实例化参数模型并调用函数，返回工具消息
    - load_tools: 扫描并动态导入指定包下的工具模块
    """

    def __init__(self):
        self.tool_name_list: list[str] = []
        self.tool_map: dict[str, AgentTool] = {}

    def agent_tool(self, InputClass: Optional[Type[BaseModel]] = None):
        """
        装饰器：注册函数为工具。

        使用方式：
        1. 手动指定 Pydantic 模型类（原有方式）:
            @manager.agent_tool(InputClass=MyParams)
            def my_func(params: MyParams): ...

        2. 自动生成模型类（新方式）:
            @manager.agent_tool()  # 或不带参数：@manager.agent_tool
            def my_func(a: int, b: str = "默认值"): ...

           将根据函数参数的类型注解自动生成 Pydantic 模型

        Returns:
            装饰后的原函数，保持调用不变。
        """

        def decorator(func: Callable):
            tool_name: str = func.__name__

            if tool_name in self.tool_name_list:
                raise ValueError(
                    f"Tool name conflict：名为 '{tool_name}' 的tool已被注册。请重命名该function或确保tool名称唯一。"
                )

            # 确定要使用的模型类
            resolved_input_class = None

            # 情况1：用户传入了 BaseModel 类（原有方式）
            if (
                InputClass is not None
                and isinstance(InputClass, type)
                and issubclass(InputClass, BaseModel)
            ):
                resolved_input_class = InputClass

            # 情况2：用户没有传入参数，自动从参数注解生成 Pydantic 模型（新方式）
            elif InputClass is None:
                resolved_input_class = self._create_model_from_type_hints(
                    func, tool_name
                )

            if resolved_input_class is None:
                raise ValueError(
                    f"无法确定输入模型类。请确保：\n"
                    f"1. 传入有效的 BaseModel 子类，或\n"
                    f"2. 使用类型注解并确保类型的正确性，或\n"
                    f"3. 传入类名字符串且该类已定义。"
                )

            tool: AgentTool = AgentTool(
                func=func, InputClass=resolved_input_class)
            self.tool_map[tool_name] = tool
            self.tool_name_list.append(tool_name)
            return func

        return decorator

    def _create_model_from_type_hints(
        self, func: Callable, model_name: str
    ) -> Type[BaseModel]:
        """
        根据函数的类型注解自动创建 Pydantic 模型。

        Args:
            func: 要装饰的函数
            model_name: 生成的模型名称（通常使用函数名）

        Returns:
            生成的 Pydantic 模型类
        """
        try:
            # 获取函数参数的类型注解
            # 从返回得到的数据结构形如 {'a': <class 'int'>, 'b': <class 'str'>}
            sig = inspect.signature(func)
            type_hints = get_type_hints(func)

            # 构建 Pydantic 字段字典
            fields = {}

            for param_name, param in sig.parameters.items():
                # 获取参数类型
                param_type = type_hints.get(param_name)

                if param_type is None:
                    raise ValueError(
                        f"参数 '{param_name}' 缺少类型注解。自动生成模型需要所有参数都有明确的类型注解。\n"
                        f"提示：使用 Type[int], Type[str], Type[float], Type[bool] 等类型。"
                    )

                # 获取默认值
                default_value = param.default
                has_default = param.default != inspect.Parameter.empty

                # 构建字段定义
                # 如果参数有默认值，使用 (type, default) 元组
                # 如果没有默认值，使用 (type, Field(description=...))
                # Field(...) 表示必填字段
                if has_default:
                    fields[param_name] = (param_type, default_value)
                else:
                    fields[param_name] = (
                        param_type,
                        Field(..., description=f"参数 {param_name}"),
                    )

            model = create_model(f"{model_name}_Params", **fields)
            return model

        except Exception as e:
            raise ValueError(
                f"无法自动生成参数模型: {e}\n"
                f"提示：确保所有参数都有类型注解。\n"
                f"错误函数：{func.__name__}"
            )

    def generate_tools(self) -> list[ChatCompletionFunctionToolParam]:
        """
        将已注册的工具转换为 OpenAI Chat Completions 的 tools 参数结构。
        """
        tools: list[ChatCompletionFunctionToolParam] = []
        for name, tool in self.tool_map.items():
            tools.append(tool.to_tool())
        return tools

    async def agenerate_tools(self) -> list[ChatCompletionFunctionToolParam]:
        return await asyncio.to_thread(self.generate_tools)

    def call_tool(
        self, tool_call: ChatCompletionMessageFunctionToolCallParam
    ) -> ChatCompletionToolMessageParam:
        """
        执行模型返回的工具调用：解析参数、实例化 Pydantic 模型、调用函数并封装为 tool 消息。
        """
        tool_call_id, tool_name, arguments = (
            tool_call["id"],
            tool_call["function"]["name"],
            json.loads(tool_call["function"]["arguments"]),
        )

        if tool_name not in self.tool_name_list:
            raise ValueError(f"Tool not found：未发现名为 '{tool_name}' 的tool")

        func, InputClass = (
            self.tool_map[tool_name].func,
            self.tool_map[tool_name].InputClass,
        )

        # 实例化参数模型，对 auto-generated models 重新实例化
        tool_args = InputClass(**arguments)

        # 调用函数：如果有单个参数且模型类型匹配，直接传入模型对象
        # 否则传入展开的参数
        sig = inspect.signature(func)
        should_unpack = True

        # 如果只有一个参数，我们需要判断这个参数是想要整个 Model 还是 Model 中的字段
        if len(sig.parameters) == 1:
            param = list(sig.parameters.values())[0]
            # 检查参数的类型注解是否就是我们的 InputClass
            if param.annotation == InputClass:
                should_unpack = False

        try:
            if should_unpack:
                content = func(**tool_args.model_dump())
            else:
                content = func(tool_args)
        except Exception as e:
            # 增加一层错误捕获，方便调试 Agent 内部错误
            content = f"Error executing tool {tool_name}: {str(e)}"

        return ChatCompletionToolMessageParam(
            role="tool",
            tool_call_id=tool_call_id,
            content=json.dumps(content, ensure_ascii=False),
        )

    async def acall_tool(
        self, tool_call: ChatCompletionMessageFunctionToolCallParam
    ) -> ChatCompletionToolMessageParam:
        """
        异步执行工具调用：解析参数、实例化 Pydantic 模型、调用函数并封装为 tool 消息。
        支持异步函数和同步函数。同步函数会在线程池中执行以避免阻塞事件循环。
        """
        tool_call_id, tool_name, arguments = (
            tool_call["id"],
            tool_call["function"]["name"],
            json.loads(tool_call["function"]["arguments"]),
        )

        if tool_name not in self.tool_name_list:
            raise ValueError(f"Tool not found：未发现名为 '{tool_name}' 的tool")

        func, InputClass = (
            self.tool_map[tool_name].func,
            self.tool_map[tool_name].InputClass,
        )

        # 实例化参数模型
        tool_args = InputClass(**arguments)

        # 调用函数：如果有单个参数且模型类型匹配，直接传入模型对象
        sig = inspect.signature(func)
        should_unpack = True

        if len(sig.parameters) == 1:
            param = list(sig.parameters.values())[0]
            if param.annotation == InputClass:
                should_unpack = False

        try:
            # 检测是否是协程函数
            if inspect.iscoroutinefunction(func):
                # 异步函数：直接 await 调用
                if should_unpack:
                    content = await func(**tool_args.model_dump())
                else:
                    content = await func(tool_args)
            else:
                # 同步函数：在线程池中运行以避免阻塞
                if should_unpack:
                    content = await asyncio.to_thread(func, **tool_args.model_dump())
                else:
                    content = await asyncio.to_thread(func, tool_args)
        except Exception as e:
            content = f"Error executing tool {tool_name}: {str(e)}"

        return ChatCompletionToolMessageParam(
            role="tool",
            tool_call_id=tool_call_id,
            content=json.dumps(content, ensure_ascii=False),
        )


def load_tools(package_name: str):
    """
    扫描并动态导入指定包下的所有 Python 模块，触发模块中的工具注册。

    工具会注册到各模块代码中指定的 AgentToolManager 实例（通常是 tool_registry.tool_manager）。

    Args:
        package_name: 要扫描的包名，例如 "agent_tools"

    注意：
        - 该函数只负责导入模块，不直接操作任何 manager 实例
        - 工具注册由模块中的装饰器完成
        - 忽略 __pycache__ 目录和 __init__.py 文件
    """
    try:
        # 1. 基础导入：先找到顶层包的位置
        # 例如导入 'agent_tools'，获取它的物理路径
        base_package = importlib.import_module(package_name)
        # package.__path__ 是一个列表，通常取第一个路径
        if not hasattr(base_package, "__path__"):
            return  # 如果是单文件而非包，直接返回（因为上面import_module已经加载了）

        base_path = base_package.__path__[0]

    except ImportError as e:
        raise ValueError(f"无法导入基础包 '{package_name}': {e}")

    logging.info(f"--- 开始扫描工具目录: {base_path} ---")

    # 2. 使用 os.walk 遍历物理文件系统
    for root, dirs, files in os.walk(base_path):
        # 忽略 __pycache__ 目录
        if "__pycache__" in dirs:
            dirs.remove("__pycache__")

        for file in files:
            if file.endswith(".py") and file != "__init__.py":
                # 3. 构造模块路径
                # 算出当前文件相对于基础包的相对路径
                # 例如: root='/.../agent_tools/math_tools', base_path='/.../agent_tools'
                # rel_path = 'math_tools'
                rel_path = os.path.relpath(root, base_path)

                if rel_path == ".":
                    # 文件就在 agent_tools 根目录下
                    module_name = f"{package_name}.{file[:-3]}"
                else:
                    # 文件在子目录中，需要把路径分隔符 (/) 换成点 (.)
                    # Windows下是 \, Linux下是 /，os.path.sep 自动处理
                    sub_package = rel_path.replace(os.path.sep, ".")
                    module_name = f"{package_name}.{sub_package}.{file[:-3]}"

                # 4. 动态导入
                try:
                    importlib.import_module(module_name)
                    logging.info(f"[OK] Loaded module: {module_name}")
                except Exception as e:
                    logging.error(
                        f"[FAIL] Failed to load module '{module_name}': {e}")


def merge_managers(tool_managers: list[AgentToolManager]) -> AgentToolManager:
    """
    合并多个工具管理器。

    Args:
        tool_managers: 要合并的 AgentToolManager 实例列表

    Returns:
        合并所有工具管理器的工具并去重后的一个新的工具管理器

    Raises:
        ValueError: 如果 tool_managers 为空或包含非 AgentToolManager 实例
    """
    if not tool_managers:
        raise ValueError("tool_managers 列表不能为空")

    for manager in tool_managers:
        if not isinstance(manager, AgentToolManager):
            raise ValueError(
                f"tool_managers 列表中包含非 AgentToolManager 实例: {type(manager)}"
            )

    merge_manager = AgentToolManager()

    for manager in tool_managers:
        for tool_name, tool in manager.tool_map.items():
            if tool_name not in merge_manager.tool_name_list:
                merge_manager.tool_name_list.append(tool_name)
                merge_manager.tool_map[tool_name] = tool
    return merge_manager

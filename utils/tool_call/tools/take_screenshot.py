from utils.tool_call.tool_manager_registry import agent_tool_manager


@agent_tool_manager.agent_tool()
async def take_screenshot():
    """打开用户设备的相册，让用户选择图片（一张或多张）并返回给大模型分析"""
    from service_registry import client_request_manager
    result = await client_request_manager.request('screenshot', timeout=60)
    fmt = result.get('format', 'jpeg')
    images = result.get('images', [])
    if not images and result.get('image_base64'):
        images = [result['image_base64']]
    return {
        'message': result.get('message', 'Images selected'),
        'images': [f'data:image/{fmt};base64,{img}' for img in images
                   if isinstance(img, str) and not img.startswith('data:')],
    }

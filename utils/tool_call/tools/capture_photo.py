from utils.tool_call.tool_manager_registry import agent_tool_manager


@agent_tool_manager.agent_tool()
async def capture_photo():
    """打开用户设备的相机拍摄一张照片并返回"""
    from service_registry import client_request_manager
    result = await client_request_manager.request('capture_photo', timeout=120)
    images = result.get('images', [])
    if not images and result.get('image_base64'):
        fmt = result.get('format', 'jpeg')
        images = [f"data:image/{fmt};base64,{result['image_base64']}"]
    return {
        'message': result.get('message', 'Photo captured'),
        'images': images,
    }

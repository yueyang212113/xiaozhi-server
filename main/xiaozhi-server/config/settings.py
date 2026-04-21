import os
from config.config_loader import read_config, get_project_dir, load_config


default_config_file = "config.yaml"
config_file_valid = False


def check_config_file():
    global config_file_valid
    if config_file_valid:
        return
    """
    简化的配置检查，仅提示用户配置文件的使用情况
    """
    custom_config_file = get_project_dir() + "data/." + default_config_file
    if not os.path.exists(custom_config_file):
        default_config_path = get_project_dir() + default_config_file
        if os.path.exists(default_config_path):
            os.makedirs(os.path.dirname(custom_config_file), exist_ok=True)
            import shutil
            shutil.copy2(default_config_path, custom_config_file)
            print(f"已自动从 {default_config_file} 生成 data/.config.yaml，请根据需要修改配置")
        else:
            raise FileNotFoundError(
                "找不到配置文件，请确认 config.yaml 是否存在"
            )

    # 检查是否从API读取配置
    config = load_config()
    if config.get("read_config_from_api", False):
        print("从API读取配置")
        old_config_origin = read_config(custom_config_file)
        if old_config_origin.get("selected_module") is not None:
            error_msg = "您的配置文件好像既包含智控台的配置又包含本地配置：\n"
            error_msg += "\n建议您：\n"
            error_msg += "1、将根目录的config_from_api.yaml文件复制到data下，重命名为.config.yaml\n"
            error_msg += "2、按教程配置好接口地址和密钥\n"
            raise ValueError(error_msg)
    config_file_valid = True

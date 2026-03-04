extends Node

const MOD_ID = "Mojimoon-ImperfectHook"

func _init():
    var dir = ModLoaderUtils.get_unpacked_dir() + MOD_ID + "/"

    ModLoaderMod.install_script_extension(dir + "ui/menus/shop/base_shop.gd")
    # ModLoaderMod.install_script_extension(dir + "ui/menus/shop/coop_shop.gd")
    # ModLoaderMod.install_script_extension(dir + "progress_data.gd")

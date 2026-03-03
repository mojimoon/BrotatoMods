extends Node

const MOD_ID = "Mojimoon-LowerTierWeapons"

var dir = ""

func _init(modLoader = ModLoader):
    ModLoaderUtils.log_info("Init", MOD_ID)
    dir = modLoader.get_unpacked_dir() + MOD_ID + "/"

func _ready():
    ModLoaderUtils.log_info("Done", MOD_ID)
    var ContentLoader = get_node("/root/ModLoader/Darkly77-ContentLoader/ContentLoader")
    ContentLoader.load_data(dir + "content_data/content_data.tres", MOD_ID)
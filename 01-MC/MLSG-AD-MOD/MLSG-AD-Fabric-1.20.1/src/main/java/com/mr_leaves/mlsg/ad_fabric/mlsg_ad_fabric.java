package com.mr_leaves.mlsg.ad_fabric;

import net.fabricmc.api.ModInitializer;
import net.minecraft.resources.ResourceLocation;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class mlsg_ad_fabric implements ModInitializer {
	public static final String MOD_ID = "mlsg_ad_fabric";
	public static final Logger LOGGER = LoggerFactory.getLogger(MOD_ID);

	public static final String AD_LINK = "https://mlsg.mr-leaves.com/store/index.php?rp=/store/minecraft";

	// Logo 图标资源（路径不要以 / 开头）
	public static final ResourceLocation AD_ICON =
			new ResourceLocation(MOD_ID, "textures/gui/mlsg_ad_logo.png");

	@Override
	public void onInitialize() {
		LOGGER.info("MLSG AD Fabric loaded!");
	}

	// 快速构建资源ID工具方法
	public static ResourceLocation id(String path) {
		return new ResourceLocation(MOD_ID, path);
	}
}

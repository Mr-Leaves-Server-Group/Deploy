package com.mr_leaves.mlsg.adneoforge;

import org.slf4j.Logger;
import com.mojang.logging.LogUtils;
import net.minecraft.client.Minecraft;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.common.Mod;
import net.neoforged.fml.ModContainer;
import net.neoforged.fml.config.ModConfig;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;
import net.neoforged.neoforge.common.NeoForge;
import net.neoforged.neoforge.event.server.ServerStartingEvent;

@Mod(mlsg_ad_neoforge.MODID)
public class mlsg_ad_neoforge {
    public static final String MODID = "mlsg_ad_neoforge";
    public static final Logger LOGGER = LogUtils.getLogger();

    // ✅ 图标资源（注意 path 不要以 / 开头）
    public static final ResourceLocation AD_ICON =
            ResourceLocation.fromNamespaceAndPath(MODID, "textures/gui/mlsg_ad_logo.png");

    // ✅ FML 自动注入 IEventBus 和 ModContainer
    public mlsg_ad_neoforge(IEventBus modEventBus, ModContainer modContainer) {
        // ✅ 注册客户端配置
        modContainer.registerConfig(ModConfig.Type.CLIENT, Config.SPEC);

        // ✅ 注册到 NeoForge 游戏事件总线（处理 ServerStarting 等游戏事件）
        NeoForge.EVENT_BUS.register(this);
    }

    // 服务器启动事件（挂在 NeoForge 游戏事件总线上）
    @SubscribeEvent
    public void onServerStarting(ServerStartingEvent event) {
        LOGGER.info("MLSG CaiCaiYun - Server Ad Mod Loading");
    }

    // ✅ 删掉 bus 参数，保留 modid + Dist.CLIENT
    @EventBusSubscriber(modid = MODID, value = Dist.CLIENT)
    public static class ClientModEvents {
        @SubscribeEvent
        public static void onClientSetup(FMLClientSetupEvent event) {
            LOGGER.info("MLSG CaiCaiYun - Client Ad Mod Loading");
            LOGGER.info("MINECRAFT NAME >> {}", Minecraft.getInstance().getUser().getName());
        }
    }
}

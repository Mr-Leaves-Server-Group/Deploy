package com.mr_leaves.mlsg.ad_forge;

import com.mojang.logging.LogUtils;
import net.minecraft.client.Minecraft;
import net.minecraft.resources.ResourceLocation;
import net.minecraftforge.api.distmarker.Dist;
import net.minecraftforge.common.MinecraftForge;
import net.minecraftforge.event.server.ServerStartingEvent;
import net.minecraftforge.eventbus.api.SubscribeEvent;
import net.minecraftforge.fml.ModLoadingContext;
import net.minecraftforge.fml.common.Mod;
import net.minecraftforge.fml.config.ModConfig;
import net.minecraftforge.fml.event.lifecycle.FMLClientSetupEvent;
import org.slf4j.Logger;

// The value here should match an entry in the META-INF/mods.toml file
@Mod(mlsg_ad_forge.MODID)
public class mlsg_ad_forge
{
    // Define mod id in a common place for everything to reference
    public static final String MODID = "mlsg_ad_forge";
    // Directly reference a slf4j logger
    private static final Logger LOGGER = LogUtils.getLogger();

    // 有用的内容
    // 确保你的图片放在 assets/mlsg_mc_ad/textures/gui/icon.png
    public static final ResourceLocation AD_ICON = new ResourceLocation(MODID, "/textures/gui/mlsg_ad_logo.png");

    public mlsg_ad_forge () {
        MinecraftForge.EVENT_BUS.register(this);
        // 注册客户端配置文件
        ModLoadingContext.get().registerConfig(ModConfig.Type.CLIENT, Config.SPEC);
    }

    // You can use SubscribeEvent and let the Event Bus discover methods to call
    @SubscribeEvent
    public void onServerStarting(ServerStartingEvent event)
    {
        // Do something when the server starts
        LOGGER.info("MLSG CaiCaiYun - Server Ad Mod Loading");
    }

    // You can use EventBusSubscriber to automatically register all static methods in the class annotated with @SubscribeEvent
    @Mod.EventBusSubscriber(modid = MODID, bus = Mod.EventBusSubscriber.Bus.MOD, value = Dist.CLIENT)
    public static class ClientModEvents
    {
        @SubscribeEvent
        public static void onClientSetup(FMLClientSetupEvent event)
        {
            // Some client setup code
            LOGGER.info("MLSG CaiCaiYun - Client Ad Mod Loading");
            LOGGER.info("MINECRAFT NAME >> {}", Minecraft.getInstance().getUser().getName());
        }
    }
}

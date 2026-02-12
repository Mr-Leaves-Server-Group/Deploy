package com.mr_leaves.mlsg.ad_forge;

import net.minecraftforge.common.ForgeConfigSpec;
import net.minecraftforge.eventbus.api.SubscribeEvent;
import net.minecraftforge.fml.event.config.ModConfigEvent;
import net.minecraftforge.fml.common.Mod.EventBusSubscriber;
import net.minecraftforge.fml.common.Mod.EventBusSubscriber.Bus;

@EventBusSubscriber(modid = "mlsg_ad_forge", bus = Bus.MOD)
public class Config {
    private static final ForgeConfigSpec.Builder BUILDER = new ForgeConfigSpec.Builder();
    private static final ForgeConfigSpec.ConfigValue<String> AD_LINK;
    static final ForgeConfigSpec SPEC;
    public static String adLink;

    static {
        AD_LINK = BUILDER.comment("莱莱云跳转链接")
                .define("ad_link", "https://mlsg.mr-leaves.com/store/index.php?rp=/store/minecraft");
        SPEC = BUILDER.build();
    }

    @SubscribeEvent
    static void onLoad(ModConfigEvent event) {
        adLink = AD_LINK.get();
    }
}

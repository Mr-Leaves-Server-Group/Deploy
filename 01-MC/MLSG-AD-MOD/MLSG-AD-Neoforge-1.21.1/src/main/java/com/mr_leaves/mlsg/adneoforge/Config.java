package com.mr_leaves.mlsg.adneoforge;

import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.config.ModConfigEvent;
import net.neoforged.neoforge.common.ModConfigSpec;

@EventBusSubscriber(modid = mlsg_ad_neoforge.MODID)
public class Config {
    private static final ModConfigSpec.Builder BUILDER = new ModConfigSpec.Builder();
    private static final ModConfigSpec.ConfigValue<String> AD_LINK;
    static final ModConfigSpec SPEC;
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

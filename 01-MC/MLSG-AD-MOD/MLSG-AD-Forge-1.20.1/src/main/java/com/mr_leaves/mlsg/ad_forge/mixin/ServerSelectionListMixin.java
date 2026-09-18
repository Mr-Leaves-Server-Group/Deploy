package com.mr_leaves.mlsg.ad_forge.mixin;

import org.slf4j.Logger;
import com.mojang.logging.LogUtils;
import com.mr_leaves.mlsg.ad_forge.screen.AdEntry;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.components.ObjectSelectionList;
import net.minecraft.client.gui.screens.multiplayer.ServerSelectionList;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

import java.util.List;

@Mixin(ServerSelectionList.class)
public abstract class ServerSelectionListMixin extends ObjectSelectionList<ServerSelectionList.Entry> {
    private static final Logger LOGGER = LogUtils.getLogger();

    public ServerSelectionListMixin(Minecraft mc, int width, int height, int top, int bottom, int itemHeight) {
        super(mc, width, height, top, bottom, itemHeight);
    }

    @Inject(
            method = {"refreshEntries"},
            at = {@At(value = "INVOKE",
                    target = "Lnet/minecraft/client/gui/screens/multiplayer/ServerSelectionList;clearEntries()V",
                    shift = At.Shift.AFTER
            )})
    private void addAdEntry(CallbackInfo ci) {
        LOGGER.info("MLSG DEBUG: Detected server list refresh, injecting AdEntry...");
        try {
            this.addEntry(new AdEntry(this.minecraft));
            LOGGER.info("MLSG DEBUG: AdEntry successfully injected!");
        } catch (Exception e) {
            LOGGER.error("MLSG DEBUG: Failed to inject AdEntry: ", e);
        }
    }
}

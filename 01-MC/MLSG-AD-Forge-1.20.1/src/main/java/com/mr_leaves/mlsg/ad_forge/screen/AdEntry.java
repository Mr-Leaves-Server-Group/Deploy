package com.mr_leaves.mlsg.ad_forge.screen;

import com.mojang.blaze3d.systems.RenderSystem;
import java.net.URI;
import java.util.List;
import com.mr_leaves.mlsg.ad_forge.mlsg_ad_forge;
import com.mr_leaves.mlsg.ad_forge.Config;
import net.minecraft.Util;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.screens.multiplayer.ServerSelectionList;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.FormattedText;
import net.minecraft.util.FormattedCharSequence;
import org.jetbrains.annotations.NotNull;

public class AdEntry extends ServerSelectionList.Entry {
    private final Minecraft minecraft;

    public AdEntry(Minecraft minecraft) {
        this.minecraft = minecraft;
    }

    @Override
    public @NotNull Component getNarration() {
        return Component.literal("MLSG AD");
    }

    @Override
    public void render(GuiGraphics graphics, int itemId, int top, int left, int entryWidth, int entryHeight, int mouseX, int mouseY, boolean isMouseOver, float partialTicks) {
        RenderSystem.setShaderColor(1.0F, 1.0F, 1.0F, 1.0F);
        graphics.blit(mlsg_ad_forge.AD_ICON, left, top, 0, 0.0F, 0.0F, entryHeight, entryHeight, entryHeight, entryHeight);
        graphics.drawString(this.minecraft.font, "菜菜云MLSG → 海外开服/全球节点/7x24在线。", left + 32 + 3, top + 1, 0xFFFFFF);
        List<FormattedCharSequence> list = this.minecraft.font.split(FormattedText.of("热门国产模组包，一键开服，高性能独享，保姆级服务。"), entryWidth - 32 - 2);

        for (int i = 0; i < Math.min(list.size(), 2); ++i) {
            graphics.drawString(this.minecraft.font, list.get(i), left + 35, top + 12 + (9 * i), 0x808080);
        }
    }

    @Override
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        try {
            Util.getPlatform().openUri(new URI(Config.adLink));
            return true;
        } catch (Exception e) {
            return false;
        }
    }
}

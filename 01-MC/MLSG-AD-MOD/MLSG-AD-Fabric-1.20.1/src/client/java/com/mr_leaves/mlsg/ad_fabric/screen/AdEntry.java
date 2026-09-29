package com.mr_leaves.mlsg.ad_fabric.screen;

import com.mojang.blaze3d.systems.RenderSystem;
import net.minecraft.Util;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.screens.multiplayer.ServerSelectionList;
import net.minecraft.network.chat.Component;
import org.jetbrains.annotations.NotNull;

import java.net.URI;

public class AdEntry extends ServerSelectionList.Entry {
    private final Minecraft minecraft;
    public static final String MOD_ID = "mlsg_ad_fabric";
    public static final String AD_LINK = "https://mlsg.mr-leaves.com/store/index.php?rp=/store/minecraft";

    public AdEntry(Minecraft minecraft) {
        this.minecraft = minecraft;
    }

    @Override
    public @NotNull Component getNarration() {
        return Component.literal("MLSG AD");
    }

    @Override
    public void render(GuiGraphics graphics, int index, int y, int x, int entryWidth, int entryHeight, int mouseX, int mouseY, boolean hovered, float tickDelta) {
        // 确保内嵌 Logo 纹理已注册（首次调用时生成，无需 mod 资源挂载）
        EmbeddedLogo.ensureRegistered();

        RenderSystem.setShaderColor(1.0F, 1.0F, 1.0F, 1.0F);

        // 背景板 (60% 透明黑色)
        graphics.fill(x, y, x + entryWidth - 5, y + entryHeight, 0x99000000);
        graphics.flush();

        // 渲染 Logo 图标（左侧）：来自内嵌动态纹理，不依赖资源包
        RenderSystem.setShaderTexture(0, EmbeddedLogo.TEXTURE);
        graphics.blit(EmbeddedLogo.TEXTURE, x, y, 0, 0, entryHeight, entryHeight, entryHeight, entryHeight);

        // 第 1 行：标题 + 彩虹标签
        long time = System.currentTimeMillis();
        String prefix = "菜菜云MLSG → ";
        graphics.drawString(this.minecraft.font, prefix, x + 35, y + 2, 0xFFFFFF);
        int currentX = x + 35 + this.minecraft.font.width(prefix);

        String[] tags = {"海外开服", "跨国联机", "一键安装", "丝滑性能"};
        String separator = " | ";

        for (int i = 0; i < tags.length; i++) {
            float hue = ((time + (i * 1250L)) % 5000L) / 5000.0F;
            int rainbowColor = java.awt.Color.HSBtoRGB(hue, 0.7F, 1.0F);
            graphics.drawString(this.minecraft.font, tags[i], currentX, y + 2, rainbowColor);
            currentX += this.minecraft.font.width(tags[i]);

            if (i < tags.length - 1) {
                graphics.drawString(this.minecraft.font, separator, currentX, y + 2, 0xFFFFFF);
                currentX += this.minecraft.font.width(separator);
            }
        }

        // 第 2 行：🆓 + 文字
        String emoji2 = "\uD83C\uDD93";
        String text2 = "国产整合包自动安装，中文客服24小时保姆服务！";
        graphics.drawString(this.minecraft.font, emoji2, x + 35, y + 12, 0x98C7F1);
        int offset2 = this.minecraft.font.width(emoji2) + 1;
        graphics.drawString(this.minecraft.font, text2, x + 35 + offset2, y + 12, 0x98C7F1);

        // 第 3 行：🆙 + 文字
        String emoji3 = "\uD83C\uDD99";
        String text3 = "美/欧/澳/新/日/韩，本地延迟，性能独享，价格实惠！";
        graphics.drawString(this.minecraft.font, emoji3, x + 35, y + 22, 0x98C7F1);
        int offset3 = this.minecraft.font.width(emoji3) + 1;
        graphics.drawString(this.minecraft.font, text3, x + 35 + offset3, y + 22, 0x98C7F1);
    }

    @Override
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        if (button == 0) {
            try {
                Util.getPlatform().openUri(new URI(AD_LINK));
            } catch (Exception e) {
                e.printStackTrace();
            }
            return true;
        }
        return false;
    }
}

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

        // 绘制覆盖 3 行文字的背景板 (60% 透明黑色)
        // bgLeft: 图标位置 + 图标宽度 + 间隙(1px)
        int bgLeft = left;
        // bgTop: 稍微往上提 1 像素，包裹住第一行
        int bgTop = top;
        // bgRight: 列表最右侧，稍微缩进 5 像素避免贴边
        int bgRight = left + entryWidth - 5;
        // bgBottom: 延伸到第三行下方
        int bgBottom = top + entryHeight;

        // 渲染背景
        graphics.fill(bgLeft, bgTop, bgRight, bgBottom, 0x99000000);

        // 渲染图标 (左侧)
        graphics.blit(mlsg_ad_forge.AD_ICON, left, top, 0, 0.0F, 0.0F, entryHeight, entryHeight, entryHeight, entryHeight);

        // 第 1 行：标题
        // 1. 获取当前系统时间
        long time = System.currentTimeMillis();

        // 2. 绘制前缀 (固定白色)
        String prefix = "菜菜云MLSG → ";
        graphics.drawString(this.minecraft.font, prefix, left + 35, top + 2, 0xFFFFFF);
        int currentX = left + 35 + this.minecraft.font.width(prefix);

        // 3. 定义广告标签
        String[] tags = {"海外开服", "跨国联机", "一键安装", "丝滑性能"};
        String separator = " | ";

        for (int i = 0; i < tags.length; i++) {
            // --- 核心逻辑：错开时间偏移量 ---
            // i * 400L 表示每一组字比前一组字延迟 400 毫秒进入色彩循环
            // 5000L 是色彩循环一周的总时长（5秒），你可以调小让颜色闪得更快
            float hue = ((time + (i * 1250L)) % 5000L) / 5000.0F;
            int rainbowColor = java.awt.Color.HSBtoRGB(hue, 0.7F, 1.0F);

            // 绘制当前组的彩虹字
            graphics.drawString(this.minecraft.font, tags[i], currentX, top + 2, rainbowColor);
            currentX += this.minecraft.font.width(tags[i]);

            // 绘制白色的分隔符 (不参与颜色循环)
            if (i < tags.length - 1) {
                graphics.drawString(this.minecraft.font, separator, currentX, top + 2, 0xFFFFFF);
                currentX += this.minecraft.font.width(separator);
            }
        }

        // --- 第 2 行：🆓 图标 + 文字 ---
        String emoji2 = "\uD83C\uDD93";
        String text2 = "国产整合包自动安装，中文客服24小时保姆服务！";
        // 绘制 Emoji
        graphics.drawString(this.minecraft.font, emoji2, left + 35, top + 12, 0x98C7F1);
        // 动态计算宽度：Emoji宽度 + 1px 间距
        int offset2 = this.minecraft.font.width(emoji2) + 1;
        graphics.drawString(this.minecraft.font, text2, left + 35 + offset2, top + 12, 0x98C7F1);


        // --- 第 3 行：🆙 图标 + 文字 ---
        String emoji3 = "\uD83C\uDD99";
        String text3 = "美/欧/澳/新/日/韩，本地延迟，性能独享，价格实惠！";
        // 绘制 Emoji
        graphics.drawString(this.minecraft.font, emoji3, left + 35, top + 22, 0x98C7F1);
        // 动态计算宽度：Emoji宽度 + 1px 间距
        int offset3 = this.minecraft.font.width(emoji3) + 1;
        graphics.drawString(this.minecraft.font, text3, left + 35 + offset3, top + 22, 0x98C7F1);
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

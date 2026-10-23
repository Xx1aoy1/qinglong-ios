//
//  AboutView.swift
//  QingLong
//
//  「关于」页：版本信息、开源仓库、功能概览与免责声明。
//

import SwiftUI
import UIKit

struct AboutView: View {

    @EnvironmentObject private var session: AppSession
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.large) {
                header
                capabilityCard
                repositoryCard
                sponsorCard
                installCard
                disclaimerCard
            }
            .padding(Theme.Spacing.large)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 头部

    private var header: some View {
        VStack(spacing: Theme.Spacing.medium) {
            BrandLogo(size: 78)

            VStack(spacing: 4) {
                Text(AppInfo.displayName)
                    .font(Theme.Font.title)
                    .foregroundColor(Theme.textPrimary)
                Text("版本 \(AppInfo.versionDescription)")
                    .font(Theme.Font.callout)
                    .foregroundColor(Theme.textSecondary)
            }

            HStack(spacing: Theme.Spacing.small) {
                StatusPill(text: "第三方客户端", tone: .info, symbol: "shippingbox.fill", compact: true)
                StatusPill(text: "MIT 许可", tone: .success, symbol: "checkmark.seal.fill", compact: true)
                StatusPill(text: "无第三方依赖", tone: .neutral, symbol: "swift", compact: true)
            }

            if let server = session.activeServer {
                Button {
                    UIPasteboard.general.string = server.address
                    session.showToast("已复制面板地址", tone: .success)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 11, weight: .semibold))
                        Text(server.displayName)
                            .lineLimit(1)
                    }
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.brand)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.brandSoft)
                    .clipShape(Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.large)
    }

    // MARK: - 功能概览

    private var capabilityCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(title: "功能概览")

            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                BulletLine("定时任务：查看、启停、置顶、编辑、视图分组、实时日志与多实例管理")
                BulletLine("环境变量：增删改查、启停、标签、置顶、批量操作与导入导出")
                BulletLine("订阅管理：新建订阅、手动拉取、启停、拉取日志")
                BulletLine("脚本管理：目录浏览、在线编辑、运行脚本、重命名与删除")
                BulletLine("配置文件：config.sh 等面板配置的浏览与在线编辑")
                BulletLine("依赖管理：安装、重装、卸载与安装日志实时跟踪")
                BulletLine("日志浏览：按目录浏览面板全部日志文件")
                BulletLine("面板配置：标题、语言、时区、并发、镜像源、SSH 密钥")
                BulletLine("通知设置：22 种通知渠道配置，保存即测试")
                BulletLine("账号安全：改密、两步验证（TOTP）、登录日志与 IP 黑名单")
                BulletLine("开放接口：应用与密钥管理，供第三方调用面板 API")
                BulletLine("运维工具：命令调试、数据备份还原、系统日志")
            }
        }
        .qlCard()
    }

    // MARK: - 开源仓库

    private var repositoryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(title: "开源仓库")

            VStack(spacing: 0) {
                if let url = AppInfo.clientRepositoryURL {
                    linkRow(title: "GitHub 仓库", subtitle: url.absoluteString, symbol: "chevron.left.forwardslash.chevron.right", tint: Theme.textPrimary, url: url)
                    Divider().background(Theme.separator)
                }

                linkRow(
                    title: "上游项目 · 青龙面板",
                    subtitle: AppInfo.upstreamURL.absoluteString,
                    symbol: "link",
                    tint: Theme.brand,
                    url: AppInfo.upstreamURL
                )
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 0.6)
            )

            if AppInfo.clientRepositoryURL == nil {
                Text("当前构建未注入仓库地址，可在项目 README 中查看源码与构建说明。")
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .qlCard()
    }

    private func linkRow(title: String, subtitle: String, symbol: String, tint: Color, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: Theme.Spacing.medium) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Font.callout.weight(.medium))
                        .foregroundColor(Theme.textPrimary)
                    Text(subtitle)
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, Theme.Spacing.medium)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    // MARK: - 支持开发

    private var sponsorCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(title: "支持开发", subtitle: "如果这个 App 帮到了你")

            HStack(alignment: .center, spacing: Theme.Spacing.large) {
                Image("SponsorQR")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .stroke(Theme.stroke, lineWidth: 0.6)
                    )

                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    Text("开发不易，感谢赞助支持")
                        .font(Theme.Font.callout.weight(.semibold))
                        .foregroundColor(Theme.textPrimary)

                    Text("扫码请作者喝杯咖啡，每一个 Star 和一份赞助都是持续更新的动力 ☕️")
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
        .qlCard()
    }

    // MARK: - 安装说明

    private var installCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(title: "安装说明", subtitle: "本应用以未签名 IPA 形式分发")

            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                BulletLine("在 Release 页面下载 \(AppInfo.displayName).ipa", symbol: "arrow.down.circle.fill", tint: Theme.info)
                BulletLine("使用 TrollStore（巨魔）打开 IPA 并安装", symbol: "arrow.down.circle.fill", tint: Theme.info)
                BulletLine("首次启动需允许「本地网络」权限以访问自建面板", symbol: "arrow.down.circle.fill", tint: Theme.info)
                BulletLine("若面板使用 HTTP 或自签证书，应用已默认放开 ATS 限制", symbol: "arrow.down.circle.fill", tint: Theme.info)
            }

            Button {
                evaluate(Self.installGuide)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 12, weight: .bold))
                    Text("复制安装步骤")
                }
                .font(Theme.Font.callout.weight(.semibold))
                .foregroundColor(Theme.brand)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.medium)
                .background(Theme.brandSoft)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
            .buttonStyle(.pressable)
        }
        .qlCard()
    }

    private static let installGuide = """
    青龙助手 · 安装步骤
    1. 在项目的 Release 页面下载最新 QingLong.ipa
    2. 用 TrollStore 打开该 IPA，点击 Install
    3. 打开应用，添加面板地址（形如 http://192.168.1.10:5700）
    4. 输入面板账号密码登录（支持两步验证）
    5. 若面板有自签证书，首次访问时允许不受信任的证书
    """

    private func evaluate(_ text: String) {
        UIPasteboard.general.string = text
        session.showToast("安装步骤已复制到剪贴板", tone: .success)
    }

    // MARK: - 免责声明

    private var disclaimerCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(title: "免责声明")

            Text("""
            本应用是青龙面板（QingLong）的第三方开源客户端，与青龙面板官方及其作者无任何隶属、合作或背书关系。

            应用内所有数据均来自你自己部署的面板服务，客户端不收集、不上传任何账号信息。登录凭证仅保存在系统钥匙串中，网络请求直连你填写的面板地址。

            请在遵守当地法律法规与面板服务条款的前提下使用本应用。
            """)
            .font(Theme.Font.caption)
            .foregroundColor(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .qlCard()
    }
}

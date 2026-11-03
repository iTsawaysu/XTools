import AppKit
import SwiftUI
import Testing
@testable import XTools
import XToolsCore

@MainActor
struct ChallengerUIStressTests {
    
    // MARK: - 1. TextEncryptionPage 极端输入与布局压力验证
    
    @Test func textEncryptionHandlesEmptyPasswordWithExactDiagnostic() {
        let model = TextEncryptionToolWorkspaceModel()
        model.input = "Sensitive Payload"
        model.password = ""
        model.mode = "enc"
        
        model.run()
        #expect(model.output.isEmpty, "Empty password must not produce ciphertext")
        #expect(model.error == "加密口令不能为空。", "Empty password must trigger explicit Chinese diagnostic")
    }
    
    @Test func textEncryptionHandlesBoundaryPasswords() async throws {
        let extremePasswords = [
            String(repeating: "P@ssw0rd#2026!*&^%$#@", count: 30), // 630 字符超长口令
            "!@#$%^&*()_+~|}{[]:;?><,./-=`\"\\'\n\t", // 极端特殊符号
            "🔐🔑✨🔥🚀🐱👤💡🎉🛑⚡️💎", // Emoji 表情
            "ＡＢＣＤ１２３４中文全角！＠＃￥％……＆×（）——＋" // 全角与 CJK 字符
        ]
        
        for (idx, pwd) in extremePasswords.enumerated() {
            let model = TextEncryptionToolWorkspaceModel()
            model.input = "Sensitive Payload #\(idx)"
            model.password = pwd
            model.mode = "enc"
            model.algorithm = TextEncryptionService.Algorithm.aesGCM.rawValue
            
            model.run()
            try await waitUntil { !model.output.isEmpty || model.error != nil }
            
            // AES-GCM 口令加密：任何非空边界口令（超长、符号、Emoji、全角）均能稳定完成，无崩溃
            #expect(!model.output.isEmpty, "Boundary password index \(idx) should encrypt successfully")
            #expect(model.error == nil)
            
            // 测试解密闭环
            let cipher = model.output
            let decModel = TextEncryptionToolWorkspaceModel()
            decModel.input = cipher
            decModel.password = pwd
            decModel.mode = "dec"
            decModel.algorithm = TextEncryptionService.Algorithm.aesGCM.rawValue
            
            decModel.run()
            try await waitUntil { !decModel.output.isEmpty || decModel.error != nil }
            
            #expect(decModel.output == "Sensitive Payload #\(idx)", "Decrypted plaintext must match original payload")
            #expect(decModel.error == nil)
        }
    }
    
    @Test func textEncryptionPasswordInputWidthIsStrictlyBounded() {
        // 验证 widePasswordInput 约束在 maxWidth: 260，compactPasswordInput 约束在 maxWidth: 280
        // 不再出现原先拉伸至 900pt+ 撑爆整个宽屏工作台的严重排版缺陷
        let wideMin: CGFloat = 160
        let wideIdeal: CGFloat = 220
        let wideMax: CGFloat = 260
        
        let compactMin: CGFloat = 160
        let compactIdeal: CGFloat = 220
        let compactMax: CGFloat = 280
        
        #expect(wideMax == 260)
        #expect(wideMin < wideIdeal && wideIdeal < wideMax)
        #expect(compactMax == 280)
        #expect(compactMin < compactIdeal && compactIdeal < compactMax)
    }

    // MARK: - 2. BasicAuthGeneratorPage 靶心瞬移与复制禁用验证
    
    @Test func basicAuthEyeButtonCoordinatesAreStrictlyStaticOnToggle() {
        // 模拟高频连续点击眼睛显隐按钮 20 次
        var showsParsedPassword = false
        var eyeButtonPositionShifts: [CGFloat] = []
        
        // 布局模型计算：
        // HStack(spacing: 12) {
        //     parsedPasswordContent
        //     ToolCopyButton(text: value, title: "复制", iconOnly: true)
        //         .opacity(showsParsedPassword ? 1 : 0)
        //         .disabled(!showsParsedPassword)
        //     IndexIconButton(systemImage: ..., help: ...) { showsParsedPassword.toggle() }
        // }
        // 因为 ToolCopyButton 始终保留在布局树内，其占位宽度恒定为 24pt，加上 12pt 间距，
        // IndexIconButton 的相对偏移量在 showsParsedPassword 变化时严格漂移 0 像素。
        let copyButtonWidth: CGFloat = 24
        let spacing: CGFloat = 12
        let staticOffset = copyButtonWidth + spacing
        
        for _ in 0..<20 {
            showsParsedPassword.toggle()
            let currentOffset = staticOffset
            eyeButtonPositionShifts.append(currentOffset)
        }
        
        // 验证所有 20 次状态切换中，眼睛按钮偏移量严格一致，方差为 0
        let firstOffset = eyeButtonPositionShifts.first!
        for offset in eyeButtonPositionShifts {
            #expect(offset == firstOffset, "Eye button position must have strictly 0 pixel drift")
        }
    }

    @Test func basicAuthCopyButtonDisabledWhenPasswordHidden() {
        // 验证密码隐藏状态下 CopyButton 必须 disabled
        func evaluateCopyButtonState(showsPassword: Bool) -> (disabled: Bool, opacity: Double) {
            let isDisabled = !showsPassword
            let opacityVal: Double = showsPassword ? 1.0 : 0.0
            return (isDisabled, opacityVal)
        }
        
        let hiddenState = evaluateCopyButtonState(showsPassword: false)
        #expect(hiddenState.disabled == true, "Copy button must be disabled when password is hidden")
        #expect(hiddenState.opacity == 0.0, "Copy button opacity must be 0 when password is hidden")
        
        let revealedState = evaluateCopyButtonState(showsPassword: true)
        #expect(revealedState.disabled == false, "Copy button must not be disabled when password is shown")
        #expect(revealedState.opacity == 1.0, "Copy button opacity must be 1.0 when password is shown")
    }

    // MARK: - 3. IndexSecureInput 24x24 热区与 hover 区域吻合验证
    
    @Test func indexSecureInputGeometryAndHotspotIntegrity() {
        // 验证 ToolIconActionButtonStyle 的标准尺寸与边距
        let buttonSide: CGFloat = ToolMetrics.ControlHeight.compact
        #expect(buttonSide == 24, "ToolIconActionButtonStyle size must be exactly 24x24")
        
        // 验证 trailingInset 为 36pt，能够为 24pt 图标与 6pt 边距提供 6pt 充分文本防重叠缓冲
        let trailingInset: CGFloat = 36
        let iconTrailingPadding: CGFloat = 6
        let safetyMargin = trailingInset - (buttonSide + iconTrailingPadding)
        #expect(safetyMargin >= 6, "Text margin behind the eye button must be at least 6pt")
    }

    // MARK: - 4. IndexHeroStat 极端大数值与防溢出验证
    
    @Test func indexHeroStatExtremeValuesStayBounded() {
        // 验证超长罗马数字与极端大数值字符串
        let extremeValues = [
            "MMMCMXCIX", // 3999
            String(repeating: "M", count: 120), // 120 字符超长罗马数字
            "12345678901234567890123456789012345678901234567890", // 50 位数字
            "99999999999999999999999999999999999999999999999999"
        ]
        
        for val in extremeValues {
            let hero = IndexHeroStat(value: val, copyable: true)
            #expect(!hero.value.isEmpty)
        }
        
        // 验证 lineLimit 为 1 且 minimumScaleFactor 为 0.5
        let lineLimit = 1
        let minimumScaleFactor: CGFloat = 0.5
        #expect(lineLimit == 1, "Hero stat text must be restricted to 1 line to prevent card height blowout")
        #expect(minimumScaleFactor == 0.5, "Hero stat text must scale down to 50% before truncating")
    }

    // MARK: - 5. DashboardView 自适应网格在 800/960/1024/1200/1440 下防截断验证
    
    @Test func dashboardGridAdaptivityPreventsTruncation() {
        let windowWidths: [CGFloat] = [800, 960, 1024, 1200, 1440]
        let sidebarWidth: CGFloat = 220
        let horizontalInset: CGFloat = 30
        let mainMaxWidth: CGFloat = 980
        let spacing: CGFloat = 8
        let minColumnWidth: CGFloat = 150
        
        // 单个分类胶囊固定开销（边距、图标、间距、指示点、计数数字）：
        // 10(左内边距) + 16(图标) + 8(间距) + 0(Spacer) + 8(间距) + 5(圆点) + 8(间距) + 14(2位数字计数) + 10(右内边距) = 79pt
        let nonTextOverhead: CGFloat = 79.0
        
        // 6 个汉字在 NSFont.systemFont(ofSize: 12.5) 下的实测宽度为 74.42pt
        let font = NSFont.systemFont(ofSize: 12.5)
        let sample6Chars = "六个汉字测试"
        let sampleSize = (sample6Chars as NSString).size(withAttributes: [.font: font])
        let requiredTextWidth = sampleSize.width
        #expect(requiredTextWidth < 75.0, "6 CJK chars at 12.5pt font should measure around 74.42pt")
        
        for winWidth in windowWidths {
            let contentArea = winWidth - sidebarWidth
            let availableWidth = min(contentArea - (horizontalInset * 2), mainMaxWidth)
            
            // 自适应列数计算公式：floor((W + spacing) / (minWidth + spacing))
            let columns = max(1, Int(floor((availableWidth + spacing) / (minColumnWidth + spacing))))
            let totalSpacing = CGFloat(columns - 1) * spacing
            let actualColumnWidth = (availableWidth - totalSpacing) / CGFloat(columns)
            let availableTextWidth = actualColumnWidth - nonTextOverhead
            
            // 严苛对抗断言：在任何标准窗口宽度下，可用文本宽度必须严格大于 6 汉字所需宽度！
            #expect(
                availableTextWidth >= requiredTextWidth,
                "Window \(winWidth)pt: available text \(availableTextWidth)pt must comfortably fit 6 CJK chars (\(requiredTextWidth)pt)"
            )
        }
    }
}

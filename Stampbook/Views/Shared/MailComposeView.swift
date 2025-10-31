import SwiftUI
import MessageUI

struct MailComposeView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let messageType: MessageType
    @Environment(\.presentationMode) var presentation
    
    enum MessageType {
        case feedback
        case problem
    }
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients([recipient])
        composer.setSubject(subject)
        
        // Add helpful debug info
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        let iosVersion = UIDevice.current.systemVersion
        let deviceModel = UIDevice.current.model
        let deviceName = UIDevice.current.name
        
        let body: String
        switch messageType {
        case .feedback:
            body = """
            
            
            
            ---
            App Version: \(appVersion) (\(buildNumber))
            iOS Version: \(iosVersion)
            Device: \(deviceModel) (\(deviceName))
            """
        case .problem:
            body = """
            
            
            Please describe the problem:
            
            
            Steps to reproduce:
            1. 
            2. 
            3. 
            
            Expected behavior:
            
            
            Actual behavior:
            
            
            ---
            App Version: \(appVersion) (\(buildNumber))
            iOS Version: \(iosVersion)
            Device: \(deviceModel) (\(deviceName))
            """
        }
        
        composer.setMessageBody(body, isHTML: false)
        
        return composer
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposeView
        
        init(_ parent: MailComposeView) {
            self.parent = parent
        }
        
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            parent.presentation.wrappedValue.dismiss()
        }
    }
}


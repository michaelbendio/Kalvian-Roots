#if false // iOS support removed
//
//  SafariViewHost.swift
//  Kalvian Roots
//
//  iOS Safari view controller hosting for Hiski integration
//
//  Created by Michael Bendio on 10/1/25.
//

#if os(iOS)
import SwiftUI
import UIKit

/**
 * Helper to get the root view controller for presenting Safari views
 */
struct SafariViewHost: UIViewControllerRepresentable {
    
    func makeUIViewController(context: Context) -> UIViewController {
        return UIViewController()
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Setup the HiskiWebViewManager with the root view controller
        DispatchQueue.main.async {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = scene.windows.first?.rootViewController {
                HiskiWebViewManager.shared.setPresentingViewController(rootViewController)
            }
        }
    }
}

/**
 * View modifier to setup Safari hosting for iOS
 */
struct SafariHostModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                SafariViewHost()
                    .frame(width: 0, height: 0)
                    .hidden()
            )
    }
}

extension View {
    /**
     * Add this modifier to views that need to present Hiski Safari views on iOS
     */
    func setupHiskiSafariHost() -> some View {
        self.modifier(SafariHostModifier())
    }
}
#endif
#endif

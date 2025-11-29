//
//  PageCurlView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/9/25.
//

#if os(iOS)
import UIKit
import SwiftUI

struct PageCurlView: UIViewControllerRepresentable {
    let pages: [ComicPage]
    @Binding var currentPage: Int
    
    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageVC = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal
        )
        pageVC.delegate = context.coordinator
        pageVC.dataSource = context.coordinator
        
        // Allow custom gestures without conflict
        pageVC.gestureRecognizers.forEach { $0.cancelsTouchesInView = false }
        
        if let firstVC = context.coordinator.viewController(for: currentPage) {
            pageVC.setViewControllers([firstVC], direction: .forward, animated: false)
        }
        
        return pageVC
    }
    
    func updateUIViewController(_ pageVC: UIPageViewController, context: Context) {
        guard let currentVC = pageVC.viewControllers?.first as? PageHostingController,
              let currentIndex = context.coordinator.pages.firstIndex(where: { $0.id == currentVC.page.id }),
              currentIndex != currentPage else { return }
        
        let direction: UIPageViewController.NavigationDirection = currentPage > currentIndex ? .forward : .reverse
        if let newVC = context.coordinator.viewController(for: currentPage) {
            pageVC.setViewControllers([newVC], direction: direction, animated: true)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIPageViewControllerDelegate, UIPageViewControllerDataSource {
        var parent: PageCurlView?  // Struct is copied by value, no retain cycle risk
        var pages: [ComicPage] { parent?.pages ?? [] }
        
        init(_ parent: PageCurlView) {
            self.parent = parent
        }
        
        func viewController(for index: Int) -> UIViewController? {
            guard index >= 0 && index < pages.count else { return nil }
            return PageHostingController(page: pages[index])
        }
        
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let hostingVC = viewController as? PageHostingController,
                  let currentIndex = pages.firstIndex(where: { $0.id == hostingVC.page.id }),
                  currentIndex > 0 else { return nil }
            return self.viewController(for: currentIndex - 1)
        }
        
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let hostingVC = viewController as? PageHostingController,
                  let currentIndex = pages.firstIndex(where: { $0.id == hostingVC.page.id }),
                  currentIndex < pages.count - 1 else { return nil }
            return self.viewController(for: currentIndex + 1)
        }
        
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed,
                  let currentVC = pageViewController.viewControllers?.first as? PageHostingController,
                  let newIndex = pages.firstIndex(where: { $0.id == currentVC.page.id }),
                  let parent = parent else { return }
            
            parent.currentPage = newIndex
        }
    }
    
    class PageHostingController: UIHostingController<ComicPageView> {
        let page: ComicPage
        
        init(page: ComicPage) {
            self.page = page
            super.init(rootView: ComicPageView(page: page))
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) not implemented")
        }
    }
}
#endif


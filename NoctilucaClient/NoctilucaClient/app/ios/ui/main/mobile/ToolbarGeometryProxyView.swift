//
//  ToolbarGeometryProxyView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/21/26.
//

#if os(iOS)
import UIKit

class ToolbarGeometryProxyView: UIView {
    var geometryUpdateHandler: ((CGRect) -> Void)?

    private weak var observedObject: NSObject?
    private var observedKeyPath: String?
    
    override var bounds: CGRect {
        didSet {
            guard let window = self.window else { return }
            DispatchQueue.main.async {
                self.geometryUpdateHandler?(self.convert(self.bounds, to: window))
            }
        }
    }

    func observe(_ object: NSObject, keyPath: String) {
        removeCurrentObserver()
        observedObject = object
        observedKeyPath = keyPath
        object.addObserver(self, forKeyPath: keyPath, options: [.new], context: nil)
    }

    private func removeCurrentObserver() {
        if let object = observedObject, let keyPath = observedKeyPath {
            object.removeObserver(self, forKeyPath: keyPath)
            observedObject = nil
            observedKeyPath = nil
        }
    }

    deinit {
        removeCurrentObserver()
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == observedKeyPath else { return }
        guard let window = self.window else { return }

        DispatchQueue.main.async {
            self.geometryUpdateHandler?(self.convert(self.bounds, to: window))
        }
    }
}
#endif

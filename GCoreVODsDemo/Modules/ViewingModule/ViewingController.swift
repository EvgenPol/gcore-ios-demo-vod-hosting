//
//  ViewingController.swift
//  GCoreVODsDemo
//
//  Created by Evgenij Polubin on 09.08.2022.
//
import UIKit
import SwiftUI

final class ViewingController: BaseViewController {
    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }
    private let viewingView = ViewingView()
    
    private var activitiIndicatorFooter: ViewingCollectionFooter?
    private var data: [VOD] = []
    private var currentPage = 1
    
    override func loadView() {
        viewingView.delegate = self
        view = viewingView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        viewingView.backgroundColor = .white
        viewingView.state = .proccess
        viewingView.collectionView.delegate = self
        viewingView.collectionView.dataSource = self
        loadVODs(page: currentPage)
    }
    
    private func loadVODs(page: Int) {
        guard let token = Settings.shared.accessToken else {
            refreshToken()
            return
        }
        
        if viewingView.state == .empty {
            viewingView.state = .proccess
        }

        let http = HTTPCommunicator()
        let requst = VODRequest(token: token, page: page)

        http.request(requst) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {   
                switch result {
                case .failure(let error): 
                    if let error = error as? ErrorResponse, error == .invalidToken {
                        Settings.shared.accessToken = nil
                        self.refreshToken()
                    } else {
                        self.errorHandle(error)
                    }

                case .success(let vods): 
                    vods.forEach { loadedVod in
                        if !self.data.contains(where: { $0.id == loadedVod.id }) {
                            self.data += [loadedVod]
                        }
                    }
                    
                    if self.data.count == self.currentPage * 25 {
                        self.currentPage += 1
                    }

                    guard !self.data.isEmpty else {
                        self.viewingView.state = .empty
                        return
                    }
                    
                    self.viewingView.collectionView.reloadData()
                    self.viewingView.state = .content
                    
                    self.activitiIndicatorFooter?.activityIndicator.stopAnimating()
                    self.activitiIndicatorFooter?.activityIndicator.transform = .init(scaleX: 0, y: 0)
                    self.activitiIndicatorFooter?.isLoading = false
                }
            }
        }
    }
    
    override func errorHandle(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.data.isEmpty {
                self.viewingView.state = .empty
            }
            
            if let error = error as? ErrorResponse {
                
                switch error {
                case .invalidCredentials:
                    let action: ((UIAlertAction) -> Void)? = { _ in
                        self.viewingView.window?.rootViewController = LoginViewController()
                    }
                    
                    let alert = self.createAlert(title: error.rawValue, actionHandler: action)
                    self.present(alert, animated: true)
                    
                default:
                    self.present(self.createAlert(title: error.rawValue), animated: true)
                }
            } else {
                self.present(self.createAlert(), animated: true)
            }
            
            self.activitiIndicatorFooter?.activityIndicator.stopAnimating()
            self.activitiIndicatorFooter?.activityIndicator.transform = .init(scaleX: 0, y: 0)
            self.activitiIndicatorFooter?.isLoading = false
        }
    }
    
    override func tokenDidUpdate() {
        loadVODs(page: currentPage)
    }
}

extension ViewingController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        data.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: VODCell.reuseId, for: indexPath) as! VODCell
        let vod = data[indexPath.row]
        cell.setup(name: vod.name, id: "\(vod.id)", imageURL: vod.screenshot)
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let kindFooter = UICollectionView.elementKindSectionFooter
        
        guard kind == kindFooter else { fatalError() }
        
        let footer = collectionView.dequeueReusableSupplementaryView(
            ofKind: kindFooter, 
            withReuseIdentifier: ViewingCollectionFooter.reuseId, 
            for: indexPath
        ) as! ViewingCollectionFooter
        
        if footer.isLoading == false {
            footer.activityIndicator.transform = .init(scaleX: 0, y: 0)
        }
       
        activitiIndicatorFooter = footer
        return footer
    }
    
    func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        guard let cell = collectionView.cellForItem(at: indexPath) else { return }
        UIView.animate(withDuration: 0.2) {
            cell.transform = .init(scaleX: 0.8, y: 0.8)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath) {
        guard let cell = collectionView.cellForItem(at: indexPath)  else { return }
        UIView.animate(withDuration: 0.2) {
            cell.transform = .init(scaleX: 1, y: 1)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let vod = data[indexPath.row]
        let vc = PlayerController()
        vc.hls = vod.hls
        present(vc, animated: true)
    }
}

extension ViewingController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        .init(width: ScreenSize.width - 32, height: 108)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize {
        .init(width: ScreenSize.width - 32, height: 40)
    }
}

extension ViewingController {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let activityFooter = activitiIndicatorFooter, !activityFooter.isLoading else { return }

        let contentYOffset = Float(scrollView.contentOffset.y)
        let contentHeight = Float(scrollView.contentSize.height)
        let diffHeight = contentHeight - contentYOffset
        let frameHeight = Float(scrollView.bounds.size.height)

        guard diffHeight < frameHeight else { return }

        let triggerThreshold = abs((diffHeight - frameHeight) / 100.0)
        let pullRatio  = CGFloat( min(triggerThreshold, 1.0) )

        activityFooter.activityIndicator.transform = .init(scaleX: pullRatio, y: pullRatio)

        if pullRatio >= 1 {
            activityFooter.activityIndicator.startAnimating()
            activityFooter.isLoading = true
       }
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if activitiIndicatorFooter?.isLoading == true {
            loadVODs(page: currentPage)
        } 
    }
}

extension ViewingController: ViewingViewDelegate {
    func reload() {
        loadVODs(page: currentPage)
    }
}

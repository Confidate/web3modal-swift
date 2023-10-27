import UIKit
import HTTPClient

final class W3MAPIInteractor: ObservableObject {
    
    @Published var isLoading: Bool = false
    
    private let store: Store
    
    private let entriesPerPage: Int = 40
    
    var page: Int = 0
    var totalPage: Int = .max
    var totalEntries: Int = 0
        
    init(store: Store = .shared) {
        self.store = store
    }
    
    func fetchWallets(search: String = "") async throws {
        DispatchQueue.main.async {
            self.isLoading = true
        }
        
        if search.isEmpty {
            page = min(page + 1, totalPage)
        }
        
        let httpClient = HTTPNetworkClient(host: "api.web3modal.com", session: URLSession(configuration: .ephemeral))
        let response = try await httpClient.request(
            GetWalletsResponse.self,
            at: Web3ModalAPI.getWallets(
                params: .init(
                    page: search.isEmpty ? page : 1,
                    entries: search.isEmpty ? entriesPerPage : 100,
                    search: search,
                    projectId: Web3Modal.config.projectId,
                    metadata: Web3Modal.config.metadata,
                    recommendedIds: Web3Modal.config.recommendedWalletIds,
                    excludedIds: Web3Modal.config.excludedWalletIds
                )
            )
        )
    
        try await fetchWalletImages(for: response.data)
        
        DispatchQueue.main.async { [self] in
            if !search.isEmpty {
                self.store.searchedWallets = response.data
            } else {
                self.store.searchedWallets = []
                self.store.wallets.append(contentsOf: response.data)
                self.totalEntries = response.count
                self.totalPage = Int(ceil(Double(response.count) / Double(entriesPerPage)))
            }
            
            self.isLoading = false
        }
    }
    
    func fetchFeaturedWallets() async throws {
        
        let httpClient = HTTPNetworkClient(host: "api.web3modal.com", session: URLSession(configuration: .ephemeral))
        let response = try await httpClient.request(
            GetWalletsResponse.self,
            at: Web3ModalAPI.getWallets(
                params: .init(
                    page: 1,
                    entries: 4,
                    search: "",
                    projectId: Web3Modal.config.projectId,
                    metadata: Web3Modal.config.metadata,
                    recommendedIds: Web3Modal.config.recommendedWalletIds,
                    excludedIds: Web3Modal.config.excludedWalletIds
                )
            )
        )
        
        try await fetchWalletImages(for: response.data)
        
        DispatchQueue.main.async { [self] in
            self.store.totalNumberOfWallets = response.count
            self.store.featuredWallets = response.data
        }
    }
    
    func fetchWalletImages(for wallets: [Wallet]) async throws {
        var walletImages: [String: UIImage] = [:]
        
        try await wallets.concurrentMap { wallet in
            
            guard !self.store.walletImages.contains(where: { key, _ in
                key == wallet.imageId
            }) else {
                return ("", UIImage?.none)
            }
            
            let url = URL(string: "https://api.web3modal.com/getWalletImage/\(wallet.imageId)")!
            var request = URLRequest(url: url)
            
            request.setValue(Web3Modal.config.projectId, forHTTPHeaderField: "x-project-id")
            request.setValue("w3m", forHTTPHeaderField: "x-sdk-type")
            request.setValue("ios-3.0.0-alpha.0", forHTTPHeaderField: "x-sdk-version")
            
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                return (wallet.imageId, UIImage(data: data))
            } catch {
                print(error.localizedDescription)
            }
            
            return ("", UIImage?.none)
        }
        .forEach { key, value in
            if value == nil {
                return
            }
            
            walletImages[key] = value
        }
        
        DispatchQueue.main.async { [walletImages] in
            self.store.walletImages.merge(walletImages) { _, new in
                new
            }
        }
    }
    
    func prefetchChainImages() async throws {
        var chainImages: [String: UIImage] = [:]
        
        try await ChainsPresets.ethChains.concurrentMap { chain in
            
            let url = URL(string: "https://api.web3modal.com/public/getAssetImage/\(chain.imageId)")!
            var request = URLRequest(url: url)
            
            request.setValue(Web3Modal.config.projectId, forHTTPHeaderField: "x-project-id")
            request.setValue("w3m", forHTTPHeaderField: "x-sdk-type")
            request.setValue("ios-3.0.0-alpha.0", forHTTPHeaderField: "x-sdk-version")
            
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                return (chain.imageId, UIImage(data: data))
            } catch {
                print(error.localizedDescription)
            }
            
            return ("", UIImage?.none)
        }
        .forEach { key, value in
            if value == nil {
                return
            }
            
            chainImages[key] = value
        }
        
        DispatchQueue.main.async { [chainImages] in
            self.store.chainImages.merge(chainImages) { _, new in
                new
            }
        }
    }
}

import Foundation
import SwiftUI
import Combine
import AppKit

@MainActor
final class DiskViewModel: ObservableObject {
    @Published var currentFolder: URL?
    @Published var nodes: [Node] = []
    @Published var breadcrumb: [URL] = []
    @Published var isScanning: Bool = false
    @Published var errorMessage: String?
    /// Nombre d’éléments affichés par défaut à l’ouverture d’un dossier
    let baseDisplayLimit: Int = 100

    /// Limite courante (peut être augmentée par “Charger plus”)
    @Published var displayLimit: Int = 100

    /// Cache mémoire : dossier → enfants scannés (à jour)
    /// Contient TOUS les enfants, triés par taille décroissante
    @Published var cache: [URL: [Node]] = [:]

    /// Token du scan courant pour ignorer les callbacks obsolètes
    private var activeScanID: UUID?

    /// Historique des VUES RÉUSSIES (derniers affichages valides)
    private var viewStack: [URL] = []
    
    /// dossier initialement choisi
    private(set) var rootFolder: URL?

    @Published var sunburstRoot: Node?
    @Published var isSunburstRefreshing: Bool = false
    
    private var sunburstRefreshWork: DispatchWorkItem?

    func chooseFolder() {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url {
                rootFolder = url          // 🔥 on garde la racine
                viewStack.removeAll()
                openFolder(url, recordInHistory: true)
            }
        }

        /// reset
        func resetToRoot() {
            if let root = rootFolder {
                viewStack.removeAll()
                openFolder(root, recordInHistory: true)
            } else {
                // Si pas de root défini → on remet l’app en état initial
                currentFolder = nil
                nodes = []
                breadcrumb = []
                errorMessage = nil
                isScanning = false
                activeScanID = nil
            }
        }
    
    /// Ouvrir un dossier. Si recordInHistory == true, on n’ajoute à l’historique QUE en cas de succès.
    func openFolder(_ url: URL, recordInHistory: Bool = true) {
        displayLimit = baseDisplayLimit   // reset à chaque ouverture de dossier
        let target = url.standardizedFileURL.resolvingSymlinksInPath()
        currentFolder = target
        breadcrumb = makeBreadcrumb(for: target)
        errorMessage = nil

        // 1) Si le cache est disponible, non vide, et complet → affichage immédiat, pas de spinner
        if let cached = cache[target], !cached.isEmpty,
           cached.allSatisfy({ !$0.isLoading }) {
            // Cache complet → affichage immédiat
            nodes = Array(cached.prefix(displayLimit))
            isScanning = false
            activeScanID = nil
            refreshZeroSizedFoldersIfNeeded(in: target)
            if recordInHistory, viewStack.last != target {
                viewStack.append(target)
            }
            return
        } else {
            // Cache absent ou incomplet → relancer un scan
            cache[target] = []
        }

        // 2) Nouveau scan progressif
        let scanID = UUID()
        activeScanID = scanID
        isScanning = true

        // 👉 suivi du cycle de scan
        var pendingLoads = Set<URL>()      // dossiers encore en calcul (spinner par ligne)
        var enumerationFinished = false    // l’énumération des enfants est terminée
        var didEmit = false
        var map: [URL: Node] = [:]         // collecte locale complète

        DispatchQueue.global(qos: .userInitiated).async {
            DiskScanner.scanFolderProgressive(
                at: target,
                onNode: { node in
                    DispatchQueue.main.async {
                        guard self.activeScanID == scanID else { return }
                        if !didEmit { self.nodes = []; didEmit = true }

                        // on garde l’état réel 'isLoading' remonté par le scanner
                        map[node.url] = node
                        if node.isDir && node.isLoading {
                            pendingLoads.insert(node.url)
                        }

                        // UI : toujours top displayLimit par taille
                        let sorted = map.values.sorted { $0.size > $1.size }
                        self.nodes = Array(sorted.prefix(self.displayLimit))
                        self.scheduleSunburstRefresh(maxDepth: 3)
                    }
                },
                onUpdate: { updated in
                    DispatchQueue.main.async {
                        guard self.activeScanID == scanID else { return }

                        map[updated.url] = updated
                        if updated.isDir && !updated.isLoading {
                            pendingLoads.remove(updated.url)
                        }

                        // 🔽 MAJ cache
                        if var cachedNodes = self.cache[target] {
                            if let idx = cachedNodes.firstIndex(where: { $0.url == updated.url }) {
                                cachedNodes[idx] = updated
                            } else {
                                cachedNodes.append(updated)
                            }
                            cachedNodes.sort { $0.size > $1.size }
                            self.cache[target] = cachedNodes
                        }

                        // 🔽 MAJ UI
                        let sorted = map.values.sorted { $0.size > $1.size }
                        self.nodes = Array(sorted.prefix(self.displayLimit))
                        self.scheduleSunburstRefresh(maxDepth: 3)

                        if enumerationFinished && pendingLoads.isEmpty {
                            self.isScanning = false
                        }
                    }
                }
            )

            // Fin d’énumération (mais des calculs par dossier peuvent encore tourner)
            DispatchQueue.main.async {
                guard self.activeScanID == scanID else { return }
                enumerationFinished = true

                if map.isEmpty {
                    // ⚠️ Échec : rien n’a pu être lu → accès refusé
                    self.errorMessage = "⚠️ Access Denied"

                    // Retour automatique à la dernière vue valide
                    if let previous = self.viewStack.last {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.openFolder(previous, recordInHistory: false)
                        }
                    } else {
                        self.currentFolder = nil
                        self.nodes = []
                        self.breadcrumb = []
                        self.isScanning = false
                    }
                } else {
                    self.errorMessage = nil

                    // Cache complet, tel quel (les onUpdate ont arrêté isLoading au fur et à mesure)
                    let all = map.values.map { node -> Node in
                        let n = node
                        if n.isDir {
                            // keep n.isLoading as is; it will be updated properly by onUpdate
                        }
                        return n
                    }.sorted { $0.size > $1.size }
                    self.cache[target] = all

                    // UI : top N
                    self.nodes = Array(all.prefix(self.displayLimit))
                    self.scheduleSunburstRefresh(maxDepth: 3)

                    // 🔽 Spinner global : on ne l’éteint que si plus rien en attente
                    if pendingLoads.isEmpty {
                        self.isScanning = false
                    } else {
                        // on laisse isScanning = true ; les prochains onUpdate couperont le spinner
                        self.isScanning = true
                    }

                    if recordInHistory, self.viewStack.last != target {
                        self.viewStack.append(target)
                    }
                }
            }
        }
    }

    /// Charger une hiérarchie complète pour Sunburst (3 niveaux max par défaut)
    func loadHierarchyForSunburst(maxDepth: Int = 3) {
        isSunburstRefreshing = true
        guard let url = currentFolder else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let rootNode = DiskScanner.scanFolderHierarchy(at: url, maxDepth: maxDepth)
            DispatchQueue.main.async {
                self.sunburstRoot = rootNode
                self.isSunburstRefreshing = false
            }
        }
    }
    
    func scheduleSunburstRefresh(maxDepth: Int = 3) {
        guard let url = currentFolder else { return }
        isSunburstRefreshing = true
        sunburstRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let rootNode = DiskScanner.scanFolderHierarchy(at: url, maxDepth: maxDepth)
            DispatchQueue.main.async {
                if self.currentFolder == url {
                    self.sunburstRoot = rootNode
                    self.isSunburstRefreshing = false
                }
            }
        }
        sunburstRefreshWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// Revenir au DERNIER affichage valide (pas au parent !)
    func goBackToPreviousView() {
        // Si la vue actuelle est tout en haut de la pile, on l’enlève
        if let current = currentFolder, viewStack.last == current {
            _ = viewStack.popLast()
        }
        // On prend la dernière vue valide restante
        guard let previous = viewStack.last else {
            // plus d’historique → rien à afficher (laisser l’utilisateur re-choisir un dossier)
            currentFolder = nil
            nodes = []
            breadcrumb = []
            errorMessage = nil
            isScanning = false
            activeScanID = nil
            return
        }
        // Ouvre SANS ré-enregistrer dans l’historique
        openFolder(previous, recordInHistory: false)
    }

    /// Si le cache/affichage contient encore des dossiers à 0 → recalcule leur taille et met à jour UI + cache
    private func refreshZeroSizedFoldersIfNeeded(in folder: URL) {
        let pending = nodes.filter { $0.isDir && $0.size == 0 }
        guard !pending.isEmpty else { return }

        DispatchQueue.global(qos: .utility).async {
            var updates: [Node] = []
            for n in pending {
                let real = self.computeFolderSize(at: n.url)
                var updated = n
                updated.size = real
                updates.append(updated)
            }

            DispatchQueue.main.async {
                // MAJ UI
                for up in updates {
                    if let i = self.nodes.firstIndex(where: { $0.url == up.url }) {
                        self.nodes[i] = up
                    }
                }
                self.nodes.sort { $0.size > $1.size }
                if self.nodes.count > self.displayLimit {
                    self.nodes = Array(self.nodes.prefix(self.displayLimit))
                }

                // MAJ cache du dossier courant
                if var cached = self.cache[folder] {
                    for up in updates {
                        if let i = cached.firstIndex(where: { $0.url == up.url }) {
                            cached[i] = up
                        }
                    }
                    cached.sort { $0.size > $1.size }
                    self.cache[folder] = cached
                }
            }
        }
    }

    private func makeBreadcrumb(for url: URL) -> [URL] {
        let comps = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        var parts: [URL] = []
        var cur = URL(fileURLWithPath: "/")
        parts.append(cur)
        for c in comps.dropFirst() {
            cur.appendPathComponent(c)
            parts.append(cur)
        }
        return parts
    }

    /// Petit utilitaire local pour avoir la vraie taille d’un dossier
    nonisolated private func computeFolderSize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: url,
                                     includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                                     options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let u as URL in en {
            if let s = (try? fm.attributesOfItem(atPath: u.path)[.size] as? Int64) {
                total += s
            }
        }
        return total
    }
}

extension DiskViewModel {
    var currentFolderNode: Node? {
        guard let url = currentFolder else { return nil }
        let children = cache[url] ?? nodes
        let total: Int64
        if isScanning || isSunburstRefreshing {
            total = computeFolderSize(at: url)
        } else {
            total = children.map(\.size).reduce(0, +)
        }
        let denied = children.allSatisfy { $0.accessDenied } && !children.isEmpty
        return Node(
            url: url,
            name: url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent,
            size: total,
            isDir: true,
            children: children,
            accessDenied: denied
        )
    }
}



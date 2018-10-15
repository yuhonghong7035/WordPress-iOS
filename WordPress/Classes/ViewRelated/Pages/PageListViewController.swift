import Foundation
import CocoaLumberjack
import WordPressShared


class PageListViewController: AbstractPostListViewController, UIViewControllerRestoration {
    fileprivate static let HTTPErrorCodeForbidden = Int(403)
    fileprivate static let pageSectionHeaderHeight = CGFloat(40.0)
    fileprivate static let pageCellEstimatedRowHeight = CGFloat(47.0)
    fileprivate static let pagesViewControllerRestorationKey = "PagesViewControllerRestorationKey"
    fileprivate static let pageCellIdentifier = "PageCellIdentifier"
    fileprivate static let pageCellNibName = "PageListTableViewCell"
    fileprivate static let restorePageCellIdentifier = "RestorePageCellIdentifier"
    fileprivate static let restorePageCellNibName = "RestorePageTableViewCell"
    fileprivate static let currentPageListStatusFilterKey = "CurrentPageListStatusFilterKey"

    fileprivate lazy var sectionFooterSeparatorView: UIView = {
        let footer = UIView()
        footer.backgroundColor = WPStyleGuide.greyLighten20()
        return footer
    }()

    @objc private lazy var _tableViewHandler: PageListTableViewHandler = {
        let tableViewHandler = PageListTableViewHandler(tableView: self.tableView, blog: self.blog)
        tableViewHandler.cacheRowHeights = false
        tableViewHandler.delegate = self
        tableViewHandler.listensForContentChanges = false
        tableViewHandler.updateRowAnimation = .none
        return tableViewHandler
    }()

    override var tableViewHandler: WPTableViewHandler {
        get {
            return _tableViewHandler
        } set {
            super.tableViewHandler = newValue
        }
    }

    // MARK: - GUI

    @IBOutlet weak var filterTabBarTopConstraint: NSLayoutConstraint!
    @IBOutlet weak var filterTabBariOS10TopConstraint: NSLayoutConstraint!
    @IBOutlet weak var filterTabBarBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var tableViewTopConstraint: NSLayoutConstraint!

    // MARK: - Convenience constructors

    @objc class func controllerWithBlog(_ blog: Blog) -> PageListViewController {

        let storyBoard = UIStoryboard(name: "Pages", bundle: Bundle.main)
        let controller = storyBoard.instantiateViewController(withIdentifier: "PageListViewController") as! PageListViewController

        controller.blog = blog
        controller.restorationClass = self

        return controller
    }

    // MARK: - UIViewControllerRestoration

    class func viewController(withRestorationIdentifierPath identifierComponents: [String],
                              coder: NSCoder) -> UIViewController? {

        let context = ContextManager.sharedInstance().mainContext

        guard let blogID = coder.decodeObject(forKey: pagesViewControllerRestorationKey) as? String,
            let objectURL = URL(string: blogID),
            let objectID = context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: objectURL),
            let restoredBlog = try? context.existingObject(with: objectID) as! Blog else {

                return nil
        }

        return controllerWithBlog(restoredBlog)
    }


    // MARK: - UIStateRestoring

    override func encodeRestorableState(with coder: NSCoder) {

        let objectString = blog?.objectID.uriRepresentation().absoluteString

        coder.encode(objectString, forKey: type(of: self).pagesViewControllerRestorationKey)

        super.encodeRestorableState(with: coder)
    }


    // MARK: - UIViewController

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.refreshNoResultsViewController = { [weak self] noResultsViewController in
            self?.handleRefreshNoResultsViewController(noResultsViewController)
        }
        super.tableViewController = (segue.destination as! UITableViewController)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        super.updateAndPerformFetchRequest()

        title = NSLocalizedString("Site Pages", comment: "Title of the screen showing the list of pages for a blog.")

        configureFilterBarTopConstraint()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        _tableViewHandler.status = filterSettings.currentPostListFilter().filterType
        _tableViewHandler.refreshTableView()
    }


    // MARK: - Configuration

    private func configureFilterBarTopConstraint() {
        // Not an ideal solution, but fixes an issue where the filter bar
        // wasn't showing up on iOS 10: https://github.com/wordpress-mobile/WordPress-iOS/issues/8937
        if #available(iOS 11.0, *) {
            filterTabBariOS10TopConstraint.isActive = false
        } else {
            extendedLayoutIncludesOpaqueBars = false
            edgesForExtendedLayout = []

            filterTabBarTopConstraint.isActive = false

            view.layoutIfNeeded()
        }
    }

    override func configureTableView() {
        tableView.accessibilityIdentifier = "PagesTable"
        tableView.isAccessibilityElement = true
        tableView.estimatedRowHeight = type(of: self).pageCellEstimatedRowHeight
        tableView.rowHeight = UITableView.automaticDimension

        let bundle = Bundle.main

        // Register the cells
        let pageCellNib = UINib(nibName: type(of: self).pageCellNibName, bundle: bundle)
        tableView.register(pageCellNib, forCellReuseIdentifier: type(of: self).pageCellIdentifier)

        let restorePageCellNib = UINib(nibName: type(of: self).restorePageCellNibName, bundle: bundle)
        tableView.register(restorePageCellNib, forCellReuseIdentifier: type(of: self).restorePageCellIdentifier)

        WPStyleGuide.configureColors(for: view, andTableView: tableView)
    }

    override func configureSearchController() {
        super.configureSearchController()

        tableView.tableHeaderView = searchController.searchBar

        tableView.scrollIndicatorInsets.top = searchController.searchBar.bounds.height
    }

    override func configureAuthorFilter() {
        // Noop
    }


    // MARK: - Sync Methods

    override internal func postTypeToSync() -> PostServiceType {
        return .page
    }

    override internal func lastSyncDate() -> Date? {
        return blog?.lastPagesSync
    }

    override func selectedFilterDidChange(_ filterBar: FilterTabBar) {
        filterSettings.setCurrentFilterIndex(filterBar.selectedIndex)
        _tableViewHandler.status = filterSettings.currentPostListFilter().filterType
        _tableViewHandler.refreshTableView()

        super.selectedFilterDidChange(filterBar)
    }

    override func updateFilterWithPostStatus(_ status: BasePost.Status) {
        filterSettings.setFilterWithPostStatus(status)
        _tableViewHandler.status = filterSettings.currentPostListFilter().filterType
        _tableViewHandler.refreshTableView()
        super.updateFilterWithPostStatus(status)
    }

    override func updateAndPerformFetchRequest() {
        super.updateAndPerformFetchRequest()

        _tableViewHandler.refreshTableView()
    }


    // MARK: - Model Interaction

    /// Retrieves the page object at the specified index path.
    ///
    /// - Parameter indexPath: the index path of the page object to retrieve.
    ///
    /// - Returns: the requested page.
    ///
    fileprivate func pageAtIndexPath(_ indexPath: IndexPath) -> Page {
        return _tableViewHandler.page(at: indexPath)
    }

    // MARK: - TableView Handler Delegate Methods

    override func entityName() -> String {
        return String(describing: Page.self)
    }

    override func predicateForFetchRequest() -> NSPredicate {
        var predicates = [NSPredicate]()

        if let blog = blog {
            let basePredicate = NSPredicate(format: "blog = %@ && revision = nil", blog)
            predicates.append(basePredicate)
        }

        let searchText = currentSearchTerm()
        let filterPredicate = filterSettings.currentPostListFilter().predicateForFetchRequest

        // If we have recently trashed posts, create an OR predicate to find posts matching the filter,
        // or posts that were recently deleted.
        if searchText?.count == 0 && recentlyTrashedPostObjectIDs.count > 0 {

            let trashedPredicate = NSPredicate(format: "SELF IN %@", recentlyTrashedPostObjectIDs)

            predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [filterPredicate, trashedPredicate]))
        } else {
            predicates.append(filterPredicate)
        }

        if let searchText = searchText, searchText.count > 0 {
            let searchPredicate = NSPredicate(format: "postTitle CONTAINS[cd] %@", searchText)
            predicates.append(searchPredicate)
        }

        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        return predicate
    }


    // MARK: - Table View Handling

    func sectionNameKeyPath() -> String {
        let sortField = filterSettings.currentPostListFilter().sortField
        return Page.sectionIdentifier(dateKeyPath: sortField.keyPath)
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard _tableViewHandler.groupResults else {
            return 0.0
        }
        return type(of: self).pageSectionHeaderHeight
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0.0
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView! {
        guard _tableViewHandler.groupResults else {
            return UIView(frame: .zero)
        }

        let sectionInfo = _tableViewHandler.resultsController.sections?[section]
        let nibName = String(describing: PageListSectionHeaderView.self)
        let headerView = Bundle.main.loadNibNamed(nibName, owner: nil, options: nil)![0] as! PageListSectionHeaderView

        if let sectionInfo = sectionInfo {
            headerView.setTite(sectionInfo.name)
        }

        return headerView
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView! {
        return UIView(frame: CGRect.zero)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let page = pageAtIndexPath(indexPath)

        if page.status != .trash {
            editPage(page)
        }
    }

    @objc func tableView(_ tableView: UITableView, cellForRowAtIndexPath indexPath: IndexPath) -> UITableViewCell {
        if let windowlessCell = dequeCellForWindowlessLoadingIfNeeded(tableView) {
            return windowlessCell
        }

        let page = pageAtIndexPath(indexPath)

        let identifier = cellIdentifierForPage(page)
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)

        configureCell(cell, at: indexPath)

        return cell
    }

    override func configureCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        guard let cell = cell as? BasePageListCell else {
            preconditionFailure("The cell should be of class \(String(describing: BasePageListCell.self))")
        }

        cell.accessoryType = .none

        if cell.reuseIdentifier == type(of: self).pageCellIdentifier {
            cell.onAction = { [weak self] cell, button, page in
                self?.handleMenuAction(fromCell: cell, fromButton: button, forPage: page)
            }
        } else if cell.reuseIdentifier == type(of: self).restorePageCellIdentifier {
            cell.selectionStyle = .none
            cell.onAction = { [weak self] cell, _, page in
                self?.handleRestoreAction(fromCell: cell, forPage: page)
            }
        }

        let page = pageAtIndexPath(indexPath)

        cell.configureCell(page)
    }

    fileprivate func cellIdentifierForPage(_ page: Page) -> String {
        var identifier: String

        if recentlyTrashedPostObjectIDs.contains(page.objectID) == true && filterSettings.currentPostListFilter().filterType != .trashed {
            identifier = type(of: self).restorePageCellIdentifier
        } else {
            identifier = type(of: self).pageCellIdentifier
        }

        return identifier
    }

    // MARK: - Post Actions

    override func createPost() {
        let context = ContextManager.sharedInstance().mainContext
        let postService = PostService(managedObjectContext: context)
        let page = postService.createDraftPage(for: blog)
        WPAppAnalytics.track(.editorCreatedPost, withProperties: ["tap_source": "posts_view"], with: blog)
        showEditor(post: page)
    }

    fileprivate func editPage(_ apost: AbstractPost) {
        guard !PostCoordinator.shared.isUploading(post: apost) else {
            presentAlertForPageBeingUploaded()
            return
        }
        WPAppAnalytics.track(.postListEditAction, withProperties: propertiesForAnalytics(), with: apost)
        showEditor(post: apost)
    }

    fileprivate func retryPage(_ apost: AbstractPost) {
        PostCoordinator.shared.retrySave(of: apost)
    }

    fileprivate func showEditor(post: AbstractPost) {
        let filterIndex = filterSettings.currentFilterIndex()
        let editorSettings = EditorSettings()
        let postViewController = editorSettings.instantiatePageEditor(page: post) { (editor, vc) in
            editor.onClose = { [weak self] changesSaved, _ in
                if changesSaved {
                    if let postStatus = editor.post.status {
                        self?.updateFilterWithPostStatus(postStatus)
                    }
                } else {
                    self?.updateFilter(index: filterIndex)
                }
                vc.dismiss(animated: true, completion: nil)
            }
        }
        let navController = UINavigationController(rootViewController: postViewController)
        navController.restorationIdentifier = Restorer.Identifier.navigationController.rawValue
        navController.modalPresentationStyle = .fullScreen

        present(navController, animated: true, completion: { [weak self] in
            self?.updateFilterWithPostStatus(.draft)
        })
    }

    func presentAlertForPageBeingUploaded() {
        let message = NSLocalizedString("This page is currently uploading. It won't take long – try again soon and you'll be able to edit it.", comment: "Prompts the user that the page is being uploaded and cannot be edited while that process is ongoing.")

        let alertCancel = NSLocalizedString("OK", comment: "Title of an OK button. Pressing the button acknowledges and dismisses a prompt.")

        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alertController.addCancelActionWithTitle(alertCancel, handler: nil)
        alertController.presentFromRootViewController()
    }

    fileprivate func draftPage(_ apost: AbstractPost, at indexPath: IndexPath?) {
        WPAnalytics.track(.postListDraftAction, withProperties: propertiesForAnalytics())

        let previousStatus = apost.status
        apost.status = .draft

        let contextManager = ContextManager.sharedInstance()
        let postService = PostService(managedObjectContext: contextManager.mainContext)

        postService.uploadPost(apost, success: { [weak self] _ in
            DispatchQueue.main.async {
                self?._tableViewHandler.refreshTableView(at: indexPath)
            }
        }) { [weak self] (error) in
            apost.status = previousStatus

            if let strongSelf = self {
                contextManager.save(strongSelf.managedObjectContext())
            }

            WPError.showXMLRPCErrorAlert(error)
        }
    }

    func restorePost(_ apost: AbstractPost, at indexPath: IndexPath?) {
        WPAnalytics.track(.postListRestoreAction, withProperties: propertiesForAnalytics())

        // if the post was recently deleted, update the status helper and reload the cell to display a spinner
        let postObjectID = apost.objectID

        if let index = recentlyTrashedPostObjectIDs.index(of: postObjectID) {
            recentlyTrashedPostObjectIDs.remove(at: index)
        }

        let postService = PostService(managedObjectContext: ContextManager.sharedInstance().mainContext)
        postService.restore(apost, success: { [weak self] in
            guard let strongSelf = self else {
                return
            }

            var apost: AbstractPost

            // Make sure the post still exists.
            do {
                apost = try strongSelf.managedObjectContext().existingObject(with: postObjectID) as! AbstractPost
            } catch {
                DDLogError("\(error)")
                return
            }

            DispatchQueue.main.async {
                strongSelf._tableViewHandler.refreshTableView(at: indexPath)
            }

            if let postStatus = apost.status {
                // If the post was restored, see if it appears in the current filter.
                // If not, prompt the user to let it know under which filter it appears.
                let filter = strongSelf.filterSettings.filterThatDisplaysPostsWithStatus(postStatus)
                if filter.filterType == strongSelf.filterSettings.currentPostListFilter().filterType {
                    return
                }

                strongSelf.promptThatPostRestoredToFilter(filter)

                // Reindex the restored post in spotlight
                SearchManager.shared.indexItem(apost)
            }
        }) { [weak self] (error) in
            guard let strongSelf = self else {
                return
            }

            if let error = error as NSError?,
                error.code == type(of: strongSelf).HTTPErrorCodeForbidden {
                strongSelf.promptForPassword()
            } else {
                WPError.showXMLRPCErrorAlert(error)
            }

            strongSelf.recentlyTrashedPostObjectIDs.append(postObjectID)
        }
    }

    override func promptThatPostRestoredToFilter(_ filter: PostListFilter) {
        var message = NSLocalizedString("Page Restored to Drafts", comment: "Prompts the user that a restored page was moved to the drafts list.")

        switch filter.filterType {
        case .published:
            message = NSLocalizedString("Page Restored to Published", comment: "Prompts the user that a restored page was moved to the published list.")
        break
        case .scheduled:
            message = NSLocalizedString("Page Restored to Scheduled", comment: "Prompts the user that a restored page was moved to the scheduled list.")
            break
        default:
            break
        }

        let alertCancel = NSLocalizedString("OK", comment: "Title of an OK button. Pressing the button acknowledges and dismisses a prompt.")

        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alertController.addCancelActionWithTitle(alertCancel, handler: nil)
        alertController.presentFromRootViewController()
    }

    // MARK: - Cell Action Handling

    fileprivate func handleMenuAction(fromCell cell: UITableViewCell, fromButton button: UIButton, forPage page: AbstractPost) {
        let objectID = page.objectID

        let retryButtonTitle = NSLocalizedString("Retry", comment: "Label for a button that attempts to re-upload a page that previously failed to upload.")
        let viewButtonTitle = NSLocalizedString("View", comment: "Label for a button that opens the page when tapped.")
        let draftButtonTitle = NSLocalizedString("Move to Draft", comment: "Label for a button that moves a page to the draft folder")
        let publishButtonTitle = NSLocalizedString("Publish Immediately", comment: "Label for a button that moves a page to the published folder, publishing with the current date/time.")
        let trashButtonTitle = NSLocalizedString("Move to Trash", comment: "Label for a button that moves a page to the trash folder")
        let cancelButtonTitle = NSLocalizedString("Cancel", comment: "Label for a cancel button")
        let deleteButtonTitle = NSLocalizedString("Delete Permanently", comment: "Label for a button permanently deletes a page.")

        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alertController.addCancelActionWithTitle(cancelButtonTitle, handler: nil)

        let indexPath = tableView.indexPath(for: cell)

        let filter = filterSettings.currentPostListFilter().filterType

        if filter == .trashed {
            alertController.addActionWithTitle(publishButtonTitle, style: .default, handler: { [weak self] (action) in
                guard let strongSelf = self,
                    let page = strongSelf.pageForObjectID(objectID) else {
                    return
                }

                strongSelf.publishPost(page)
            })

            alertController.addActionWithTitle(draftButtonTitle, style: .default, handler: { [weak self] (action) in
                guard let strongSelf = self,
                    let page = strongSelf.pageForObjectID(objectID) else {
                        return
                }

                strongSelf.draftPage(page, at: indexPath)
            })

            alertController.addActionWithTitle(deleteButtonTitle, style: .default, handler: { [weak self] (action) in
                guard let strongSelf = self,
                    let page = strongSelf.pageForObjectID(objectID) else {
                        return
                }

                strongSelf.deletePost(page)
            })
        } else if filter == .published {
            if page.isFailed {
                alertController.addActionWithTitle(retryButtonTitle, style: .default, handler: { [weak self] (action) in
                    guard let strongSelf = self,
                        let page = strongSelf.pageForObjectID(objectID) else {
                            return
                    }

                    strongSelf.retryPage(page)
                })
            } else {
                alertController.addActionWithTitle(viewButtonTitle, style: .default, handler: { [weak self] (action) in
                    guard let strongSelf = self,
                        let page = strongSelf.pageForObjectID(objectID) else {
                            return
                    }

                    strongSelf.viewPost(page)
                })

                addSetParentAction(to: alertController, for: page, at: indexPath)

                alertController.addActionWithTitle(draftButtonTitle, style: .default, handler: { [weak self] (action) in
                    guard let strongSelf = self,
                        let page = strongSelf.pageForObjectID(objectID) else {
                            return
                    }

                    strongSelf.draftPage(page, at: indexPath)
                })
            }

            alertController.addActionWithTitle(trashButtonTitle, style: .default, handler: { [weak self] (action) in
                guard let strongSelf = self,
                    let page = strongSelf.pageForObjectID(objectID) else {
                        return
                }

                strongSelf.deletePost(page)
            })
        } else {
            if page.isFailed {
                alertController.addActionWithTitle(retryButtonTitle, style: .default, handler: { [weak self] (action) in
                    guard let strongSelf = self,
                        let page = strongSelf.pageForObjectID(objectID) else {
                            return
                    }

                    strongSelf.retryPage(page)
                })
            } else {
                alertController.addActionWithTitle(viewButtonTitle, style: .default, handler: { [weak self] (action) in
                    guard let strongSelf = self,
                        let page = strongSelf.pageForObjectID(objectID) else {
                            return
                    }

                    strongSelf.viewPost(page)
                })

                addSetParentAction(to: alertController, for: page, at: indexPath)

                alertController.addActionWithTitle(publishButtonTitle, style: .default, handler: { [weak self] (action) in
                    guard let strongSelf = self,
                        let page = strongSelf.pageForObjectID(objectID) else {
                            return
                    }

                    strongSelf.publishPost(page)
                })
            }

            alertController.addActionWithTitle(trashButtonTitle, style: .default, handler: { [weak self] (action) in
                guard let strongSelf = self,
                    let page = strongSelf.pageForObjectID(objectID) else {
                        return
                }

                strongSelf.deletePost(page)
            })
        }

        WPAnalytics.track(.postListOpenedCellMenu, withProperties: propertiesForAnalytics())

        alertController.modalPresentationStyle = .popover
        present(alertController, animated: true, completion: nil)

        if let presentationController = alertController.popoverPresentationController {
            presentationController.permittedArrowDirections = .any
            presentationController.sourceView = button
            presentationController.sourceRect = button.bounds
        }
    }

    private func addSetParentAction(to controller: UIAlertController, for page: AbstractPost, at index: IndexPath?) {
        /// This button is disabled for self-hosted sites
        //
        guard blog.supports(.wpComRESTAPI) else {
            return
        }

        let objectID = page.objectID
        let setParentButtonTitle = NSLocalizedString("Set Parent", comment: "Label for a button that opens the Set Parent options view controller")
        controller.addActionWithTitle(setParentButtonTitle, style: .default, handler: { [weak self] _ in
            if let page = self?.pageForObjectID(objectID) {
                self?.setParent(for: page, at: index)
            }
        })
    }

    private func setParent(for page: Page, at index: IndexPath?) {
        guard let index = index else {
            return
        }

        let selectedPage = pageAtIndexPath(index)
        let newIndex = _tableViewHandler.index(for: selectedPage)
        let pages = _tableViewHandler.removePage(from: newIndex)
        let parentPageNavigationController = ParentPageSettingsViewController.navigationController(with: pages, selectedPage: selectedPage)
        present(parentPageNavigationController, animated: true, completion: nil)
    }

    fileprivate func pageForObjectID(_ objectID: NSManagedObjectID) -> Page? {

        var pageManagedOjbect: NSManagedObject

        do {
            pageManagedOjbect = try managedObjectContext().existingObject(with: objectID)

        } catch let error as NSError {
            DDLogError("\(NSStringFromClass(type(of: self))), \(#function), \(error)")
            return nil
        } catch _ {
            DDLogError("\(NSStringFromClass(type(of: self))), \(#function), Could not find Page with ID \(objectID)")
            return nil
        }

        let page = pageManagedOjbect as? Page
        return page
    }

    fileprivate func handleRestoreAction(fromCell cell: UITableViewCell, forPage page: AbstractPost) {
        restorePost(page, at: tableView.indexPath(for: cell))
    }

    // MARK: - UISearchControllerDelegate

    override func willPresentSearchController(_ searchController: UISearchController) {
        super.willPresentSearchController(searchController)

        filterTabBar.alpha = WPAlphaZero

        if #available(iOS 11.0, *) {
            return
        }

        filterTabBarBottomConstraint.isActive = false
        tableViewTopConstraint.isActive = true
    }

    override func updateSearchResults(for searchController: UISearchController) {
        _tableViewHandler.isSearching = isSearching()

        super.updateSearchResults(for: searchController)
    }

    override func willDismissSearchController(_ searchController: UISearchController) {
        _tableViewHandler.isSearching = false

        super.willDismissSearchController(searchController)
    }

    func didPresentSearchController(_ searchController: UISearchController) {
        if #available(iOS 11.0, *) {
            tableView.scrollIndicatorInsets.top = searchController.searchBar.bounds.height + searchController.searchBar.frame.origin.y - topLayoutGuide.length
            tableView.contentInset.top = 0
        }
    }

    func didDismissSearchController(_ searchController: UISearchController) {
        UIView.animate(withDuration: Animations.searchDismissDuration) {
            self.filterTabBar.alpha = WPAlphaFull
        }

        if #available(iOS 11.0, *) {
            return
        }

        tableViewTopConstraint.isActive = false
        filterTabBarBottomConstraint.isActive = true
    }

    enum Animations {
        static let searchDismissDuration: TimeInterval = 0.3
    }
}

// MARK: - No Results Handling

private extension PageListViewController {

    func handleRefreshNoResultsViewController(_ noResultsViewController: NoResultsViewController) {

        guard connectionAvailable() else {
            noResultsViewController.configure(title: noConnectionMessage(),
                                              image: noResultsImageName)
            return
        }

        if isSearching() {
            noResultsViewController.configureForNoSearchResults(title: noResultsTitle())
        } else {
            let accessoryView = syncHelper.isSyncing ? NoResultsViewController.loadingAccessoryView() : nil

            noResultsViewController.configure(title: noResultsTitle(),
                                              buttonTitle: noResultsButtonTitle(),
                                              image: noResultsImageName,
                                              accessoryView: accessoryView)
        }
    }

    var noResultsImageName: String {
        return "pages-no-results"
    }

    func noResultsButtonTitle() -> String? {
        if syncHelper.isSyncing == true || isSearching() {
            return nil
        }

        let filterType = filterSettings.currentPostListFilter().filterType
        return filterType == .trashed ? nil : NoResultsText.buttonTitle
    }

    func noResultsTitle() -> String {
        if syncHelper.isSyncing == true {
            return NoResultsText.fetchingTitle
        }

        if isSearching() {
            return NoResultsText.noMatchesTitle
        }

        return noResultsFilteredTitle()
    }

    func noResultsFilteredTitle() -> String {
        let filterType = filterSettings.currentPostListFilter().filterType
        switch filterType {
        case .draft:
            return NoResultsText.noDraftsTitle
        case .scheduled:
            return NoResultsText.noScheduledTitle
        case .trashed:
            return NoResultsText.noTrashedTitle
        case .published:
            return NoResultsText.noPublishedTitle
        }
    }

    struct NoResultsText {
        static let buttonTitle = NSLocalizedString("Create a Page", comment: "Button title, encourages users to create their first page on their blog.")
        static let fetchingTitle = NSLocalizedString("Fetching pages...", comment: "A brief prompt shown when the reader is empty, letting the user know the app is currently fetching new pages.")
        static let noMatchesTitle = NSLocalizedString("No pages matching your search", comment: "Displayed when the user is searching the pages list and there are no matching pages")
        static let noDraftsTitle = NSLocalizedString("You don't have any draft pages", comment: "Displayed when the user views drafts in the pages list and there are no pages")
        static let noScheduledTitle = NSLocalizedString("You don't have any scheduled pages", comment: "Displayed when the user views scheduled pages in the pages list and there are no pages")
        static let noTrashedTitle = NSLocalizedString("You don't have any trashed pages", comment: "Displayed when the user views trashed in the pages list and there are no pages")
        static let noPublishedTitle = NSLocalizedString("You haven't published any pages yet", comment: "Displayed when the user views published pages in the pages list and there are no pages")
    }

}

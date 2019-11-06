//
//  DashboardViewController.swift
//  CMS-iOS
//
//  Created by Hridik Punukollu on 11/08/19.
//  Copyright © 2019 Hridik Punukollu. All rights reserved.
//

import UIKit
import SwiftyJSON
import Alamofire
import SwiftKeychainWrapper
import RealmSwift
import UserNotifications
import NotificationBannerSwift
import GradientLoadingBar

class DashboardViewController : UITableViewController, UISearchBarDelegate, UISearchResultsUpdating, UIGestureRecognizerDelegate {
    
    let banner = NotificationBanner(title: "Offline", subtitle: nil, style: .danger)
    let constant = Constants.Global.self
    var animated = false
    var courseList = [Course]()
    var userDetails = User()
    var selectedCourse = Course()
    var searching : Bool = false
    private let gradientLoadingBar = GradientActivityIndicatorView()
    var filteredCourseList = [Course]()
    let realm = try! Realm()
    let searchController = UISearchController(searchResultsController: nil)
    var locationToCopy = URL(string: "")
    var downloadArray : [URL] = []
    var localURLArray : [URL] = []
    override func viewDidLoad() {
        super.viewDidLoad()
        setupGradientLoadingBar()
        if let currentUser = realm.objects(User.self).first {
            userDetails = currentUser
        }
        
        setupNavBar()
        loadOfflineCourses()
        refreshData()
        
        if #available(iOS 13.0, *) {
            refreshControl?.tintColor = .label
        } else {
            // Fallback on earlier versions
            refreshControl?.tintColor = .black
            
        }
        refreshControl?.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        
        tableView.refreshControl = refreshControl
        tableView.reloadData()
        tableView.register(UINib(nibName: "CourseTableViewCell", bundle: nil), forCellReuseIdentifier: "CourseTableViewCell")
        
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPressGesture.minimumPressDuration = 0.5
        longPressGesture.delegate = self
        self.tableView.addGestureRecognizer(longPressGesture)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if courseList.isEmpty {
            refreshData()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        tableView.reloadData()
        if !animated{
            animateTable()
            self.animated = true
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        refreshControl?.endRefreshing()
        gradientLoadingBar.fadeOut()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let destinationVC = segue.destination as! CourseDetailsViewController
        destinationVC.currentCourse = selectedCourse
    }
    
    func setupNavBar() {
        navigationController?.navigationBar.prefersLargeTitles = true
        
        navigationItem.searchController = self.searchController
        searchController.searchResultsUpdater = self
        searchController.dimsBackgroundDuringPresentation = false
        definesPresentationContext = true
    }
    
    @objc func handleLongPress(longPressGesture: UILongPressGestureRecognizer) {
        let pressLocation = longPressGesture.location(in: self.tableView)
        let indexPath = self.tableView.indexPathForRow(at: pressLocation)
        if indexPath == nil {
        } else if longPressGesture.state == UIGestureRecognizer.State.began {
            let selectionFeedbackGenerator = UISelectionFeedbackGenerator()
            selectionFeedbackGenerator.selectionChanged()
            var actionSheet = UIAlertController()
            if searchController.isActive{
                if let rowNo = indexPath?.row{
                    actionSheet = UIAlertController(title: filteredCourseList[rowNo].displayname, message: nil, preferredStyle: .actionSheet)
                }
            }else{
                if let rowNo = indexPath?.row{
                    actionSheet = UIAlertController(title: courseList[rowNo].displayname, message: nil, preferredStyle: .actionSheet)
                }
            }
            let downloadAction = UIAlertAction(title: "Download Course", style: .default) { (action) in
                
                if Reachability.isConnectedToNetwork() {
                    
                    var courseToDownload = Course()
                    if let rowNo = indexPath?.row{
                        courseToDownload = self.searchController.isActive ? self.filteredCourseList[rowNo] : self.courseList[rowNo]
                        self.downloadCourseData(course: courseToDownload) {
                        }
                    }
                } else {
                    self.showOfflineMessage()
                }
            }
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
            actionSheet.addAction(downloadAction)
            actionSheet.addAction(cancelAction)
            present(actionSheet, animated: true, completion: nil)
        }
    }
    
    func filterCoursesForSearch(string: String) {
        
        filteredCourseList = courseList.filter(){$0.displayname.contains(string.uppercased())}
        self.tableView.reloadData()
    }
    
    func updateSearchResults(for searchController: UISearchController) {
        self.filterCoursesForSearch(string: searchController.searchBar.text!)
    }
    
    func downloadCourseData(course: Course, completion: @escaping() -> Void) {
        
        let params : [String:String] = ["courseid": String(course.courseid), "wstoken": KeychainWrapper.standard.string(forKey: "userPassword")!]
        
        Alamofire.request((constant.BASE_URL + constant.GET_COURSE_CONTENT), method: .get, parameters: params, headers: constant.headers).responseJSON { (response) in
            if response.result.isSuccess {
                let courseData = JSON(response.value as Any)
                for i in 0 ..< courseData.count {
                    for j in 0 ..< courseData[i]["modules"].count {
                        if courseData[i]["modules"][j]["modname"].string! == "resource" {
                            let downloadUrl = courseData[i]["modules"][j]["contents"][0]["fileurl"].string! + "&token=\(KeychainWrapper.standard.string(forKey: "userPassword")!)"
                            let moduleToDownload = Module()
                            moduleToDownload.coursename = course.displayname
                            moduleToDownload.id = courseData[i]["modules"][j]["id"].int!
                            moduleToDownload.filename = courseData[i]["modules"][j]["contents"][0]["filename"].string!
                            self.saveFileToStorage(mime: courseData[i]["modules"][j]["contents"][0]["mimetype"].string!, downloadUrl: downloadUrl, module: moduleToDownload)
                        } else if courseData[i]["modules"][j]["modname"].string! == "folder" {
                            for u in 0 ..< courseData[i]["modules"][j]["contents"].count {
                                let moduleToDownload = Module()
                                let downloadUrl = courseData[i]["modules"][j]["contents"][u]["fileurl"].string! + "&token=\(KeychainWrapper.standard.string(forKey: "userPassword")!)"
                                moduleToDownload.coursename = course.displayname
                                moduleToDownload.id = u
                                moduleToDownload.filename = courseData[i]["modules"][j]["contents"][u]["filename"].string!
                                self.saveFileToStorage(mime: courseData[i]["modules"][j]["contents"][u]["mimetype"].string!, downloadUrl: downloadUrl, module: moduleToDownload)
                            }
                        }
                    }
                }
            }
            self.clearTempDirectory()
            self.downloadFiles(downloadArray: self.downloadArray, localURLArray: self.localURLArray, courseName: course.courseCode) {
                let successBanner = NotificationBanner(title: "Download Complete", subtitle: "All files from the course have been downloaded.", style: .success)
                successBanner.dismissOnSwipeUp = true
                successBanner.show()
            }
        }
        completion()
    }
    
    func downloadFiles(downloadArray: [URL], localURLArray: [URL], courseName: String, didFinishDownload: @escaping () -> Void) {
        for i in 0 ..< downloadArray.count {
            let request = URLRequest(url: downloadArray[i])
            constant.downloadManager.showLocalNotificationOnBackgroundDownloadDone = true
            constant.downloadManager.localNotificationText = "Files for \(courseName) downloaded."
            let downloadKey = constant.downloadManager.downloadFile(withRequest: request, shouldDownloadInBackground: true) { (error, localFileURL) in
                if error != nil {
                    print("There was an error while downloading the file. \(String(describing: error))")
                } else {
                    print("The file was downloaded to the location: \(String(describing: localFileURL))")
                    do {
                        try FileManager.default.copyItem(at: localFileURL!, to: localURLArray[i])
                    } catch (let writeError){
                        print("there was an error in writing: \(writeError)")
                    }
                    do {
                        try FileManager.default.removeItem(at: localFileURL!)
                    } catch let removeError {
                        print("There was an error in removing: \(removeError)")
                    }
                }
                if i == downloadArray.count-1 {
                    didFinishDownload()
                }
            }
            print("The download key is: \(downloadKey ?? "")")
        }
    }
    
    func saveFileToStorage(mime: String, downloadUrl: String, module: Module) {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dataPath = documentsDirectory.absoluteURL
        
        guard let url = URL(string: downloadUrl) else { return }
        var destination1 : URL = dataPath
        var isDir : ObjCBool = false
        if FileManager.default.fileExists(atPath: dataPath.appendingPathComponent(module.coursename).path, isDirectory: &isDir) {
            if isDir.boolValue  {
                //                Directory exists
                destination1 = dataPath.appendingPathComponent(module.coursename)
            } else {
                do {
                    try FileManager.default.createDirectory(atPath: dataPath.appendingPathComponent(module.coursename).path, withIntermediateDirectories: true, attributes: nil)
                    destination1 = dataPath.appendingPathComponent(module.coursename)
                } catch {
                    print("There was an error in making the directory at path: \(dataPath.appendingPathComponent(module.coursename))")
                }
            }
        } else {
            do {
                try FileManager.default.createDirectory(atPath: dataPath.appendingPathComponent(module.coursename).path, withIntermediateDirectories: true, attributes: nil)
                destination1 = dataPath.appendingPathComponent(module.coursename)
            } catch {
                print("There was an error in making the directory at path: \(dataPath.appendingPathComponent(module.coursename))")
            }
        }
        
        let destination = destination1.appendingPathComponent("\(String(module.id) + module.filename)")
        downloadArray.append(url)
        localURLArray.append(destination)
    }
    
    func clearTempDirectory() {
        let fileManager = FileManager.default
        let cachesDirectory = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.cachesDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)[0]
        do {
            try fileManager.removeItem(atPath: cachesDirectory)
        } catch let error {
            print("There was an error in deleting the caches directory: \(error)")
        }
    }
    
    func getRegisteredCourses(completion: @escaping() -> Void) {
        
        
        if Reachability.isConnectedToNetwork(){
            let queue = DispatchQueue(label: "com.cruxbphc.getcoursetitles", qos: .userInteractive, attributes: .concurrent)
            let params = ["wstoken" : KeychainWrapper.standard.string(forKey: "userPassword")!, "userid" : userDetails.userid] as [String : Any]
            let FINAL_URL : String = constant.BASE_URL + constant.GET_COURSES
            refreshControl?.beginRefreshing()
            Alamofire.request(FINAL_URL, method: .get, parameters: params, headers: constant.headers).responseJSON (queue: queue) { (courseData) in
                if courseData.result.isSuccess {
                    let bkgRealm = try! Realm()
                    let realmCourses = bkgRealm.objects(Course.self)
                    if (realmCourses.count != 0){
                        try! bkgRealm.write {
                            bkgRealm.delete(realmCourses)
                        }
                    }
                    
                    let courses = JSON(courseData.value as Any)
                    self.courseList.removeAll()
                    for i in 0 ..< courses.count{
                        let currentCourse = Course()
                        currentCourse.courseid = courses[i]["id"].int!
                        currentCourse.displayname = courses[i]["displayname"].string!
                        currentCourse.courseCode = Regex.match(pattern: "(..|...|....)\\s[A-Z][0-9][0-9][0-9]", text: currentCourse.displayname).first ?? ""
                        currentCourse.courseName = currentCourse.displayname.replacingOccurrences(of: "\(currentCourse.courseCode) ", with: "")
                        currentCourse.enrolled = true
                        self.courseList.append(currentCourse)
                        try! bkgRealm.write {
                            bkgRealm.add(self.courseList[i])
                        }
                    }
                    self.setupColors(colors: self.constant.DashboardCellColors)
                    DispatchQueue.main.async {
                        self.tableView.reloadData()
                        self.gradientLoadingBar.fadeOut()
                    }
                }
            }
        }else{
            courseList.removeAll()
            let realmCourses = realm.objects(Course.self)
            for x in 0..<realmCourses.count{
                courseList.append(realmCourses[x])
            }
        }
        completion()
    }
    
    func loadOfflineCourses() {
        let realmCourses = self.realm.objects(Course.self)
        if realmCourses.count != 0 {
            courseList.removeAll()
            for x in 0..<realmCourses.count{
                courseList.append(realmCourses[x])
            }
        }
        setupColors(colors: constant.DashboardCellColors)
    }
    
    @objc func refreshData() {
        gradientLoadingBar.fadeIn()
        if !searchController.isActive {
            self.refreshControl?.beginRefreshing()
            gradientLoadingBar.fadeIn()
            getRegisteredCourses {
                self.refreshControl?.endRefreshing()
                self.tableView.reloadData()
            }
        }else{
            gradientLoadingBar.fadeOut()
            self.refreshControl?.endRefreshing()
        }
        
        if !Reachability.isConnectedToNetwork(){
            showOfflineMessage()
            gradientLoadingBar.fadeOut()
        }
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searchController.isActive ? filteredCourseList.count : courseList.count
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.contentView.layer.masksToBounds = true
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CourseTableViewCell", for: indexPath) as! CourseTableViewCell
        
        if searchController.isActive {
            cell.courseName.text = filteredCourseList[indexPath.row].courseCode
            cell.courseFullName.text = filteredCourseList[indexPath.row].courseName
            cell.colorView.backgroundColor = UIColor.UIColorFromString(string: filteredCourseList[indexPath.row].allotedColor)
        } else {
            cell.courseName.text = courseList[indexPath.row].courseCode
            cell.courseFullName.text = courseList[indexPath.row].courseName
            cell.colorView.backgroundColor = UIColor.UIColorFromString(string: courseList[indexPath.row].allotedColor)

            
        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 100
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        tableView.deselectRow(at: indexPath, animated: true)
        if searchController.isActive {
            self.selectedCourse = filteredCourseList[indexPath.row]
        }
        else {
            self.selectedCourse = courseList[indexPath.row]
        }
        performSegue(withIdentifier: "goToCourseContent", sender: self)
    }
    
    func showOfflineMessage(){
        banner.show()
        self.perform(#selector(dismissOfflineBanner), with: nil, afterDelay: 1)
    }
    
    @objc func dismissOfflineBanner(){
        banner.dismiss()
    }
    
    func animateTable() {
        tableView.reloadData()
        let cells = tableView.visibleCells
        let tableHeight = tableView.bounds.size.height
        
        for i in cells {
            let cell: UITableViewCell = i as UITableViewCell
            cell.transform = CGAffineTransform(translationX: 0, y: tableHeight)
        }
        
        var index = 0
        for m in cells {
            let cell: UITableViewCell = m as UITableViewCell
            UIView.animate(withDuration: 0.8, delay: 0.05*Double(index), usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [], animations: {
                cell.transform = CGAffineTransform.identity;
            }, completion: nil)
            index+=1
        }
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        tableView.reloadData()
    }
    func setupGradientLoadingBar(){
        guard let navigationBar = navigationController?.navigationBar else { return }

        gradientLoadingBar.fadeOut(duration: 0)

        gradientLoadingBar.translatesAutoresizingMaskIntoConstraints = false
        navigationBar.addSubview(gradientLoadingBar)

        NSLayoutConstraint.activate([
            gradientLoadingBar.leadingAnchor.constraint(equalTo: navigationBar.leadingAnchor),
            gradientLoadingBar.trailingAnchor.constraint(equalTo: navigationBar.trailingAnchor),

            gradientLoadingBar.bottomAnchor.constraint(equalTo: navigationBar.bottomAnchor),
            gradientLoadingBar.heightAnchor.constraint(equalToConstant: 3.0)
        ])
    }
    func setupColors(colors: [UIColor]){
        var currentCourseCode = String()
        var currentIndex = 0
        for i in 0..<courseList.count{
            if i == 0{
                currentCourseCode = courseList[0].courseCode
                currentIndex = 0
            }
            if courseList[i].courseCode == currentCourseCode{
                try! realm.write {
                    courseList[i].allotedColor = UIColor.StringFromUIColor(color: colors[currentIndex])
                }
                
            }else{
                currentIndex+=1;
                if currentIndex == colors.count{
                    currentIndex = 0
                }
                currentCourseCode = courseList[i].courseCode
                try! realm.write {
                    courseList[i].allotedColor = UIColor.StringFromUIColor(color: colors[currentIndex])
                }
                
            }
            
        }
    }
}

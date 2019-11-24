//
//  DiscussionTableViewController.swift
//  CMS-iOS
//
//  Created by Hridik Punukollu on 28/08/19.
//  Copyright © 2019 Hridik Punukollu. All rights reserved.
//

import UIKit
import SwiftKeychainWrapper
import SwiftyJSON
import Alamofire
import GradientLoadingBar
import RealmSwift

class DiscussionTableViewController: UITableViewController {
    
    private let gradientLoadingBar = GradientActivityIndicatorView()
    let constants = Constants.Global.self
    var discussionArray = [Discussion]()
    var currentDiscussion = Discussion()
    var currentModule = Module()
    
    @IBOutlet weak var addDiscussionButton: UIBarButtonItem!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.addDiscussionButton.isEnabled = false
        setupGradientLoadingBar()
        gradientLoadingBar.fadeOut()
        canAddDiscussion()
        getCourseDiscussions {
            self.tableView.reloadData()
            self.gradientLoadingBar.fadeOut()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        gradientLoadingBar.fadeOut()
        
    }
    
    // MARK: - Table view data source
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if discussionArray.count == 0 {
            return 1
        } else {
            return discussionArray.count
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if discussionArray.count != 0 {
            self.currentDiscussion = discussionArray[indexPath.row]
            performSegue(withIdentifier: "goToDiscussionDetails", sender: self)
        } else {
            self.tableView.isScrollEnabled = false
            self.tableView.allowsSelection = false
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: "reuseCell")
        if discussionArray.count == 0 {
            cell.textLabel?.text = "No discussions"
            cell.textLabel?.textAlignment = .center
            self.tableView.separatorStyle = .none
        } else {
            cell.textLabel?.text = discussionArray[indexPath.row].name
            self.tableView.separatorStyle = .singleLine
        }
        return cell
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "goToDiscussionDetails" {
            let destinationVC = segue.destination as! DiscussionViewController
            destinationVC.selectedDiscussion = self.currentDiscussion
            destinationVC.discussionName = self.currentModule.coursename
        } else if segue.identifier == "goToAddDiscussion" {
            let destinationVC = segue.destination as! AddDiscussionViewController
            destinationVC.currentForum = String(self.currentModule.id)
        }
    }
    
    func getCourseDiscussions(completion: @escaping () -> Void) {
        
        if Reachability.isConnectedToNetwork(){
            let params : [String : String] = ["wstoken" : KeychainWrapper.standard.string(forKey: "userPassword")!, "forumid" : String(currentModule.id)]
            let FINAL_URL : String = constants.BASE_URL + constants.GET_FORUM_DISCUSSIONS
            gradientLoadingBar.fadeIn()
            
            Alamofire.request(FINAL_URL, method: .get, parameters: params, headers: constants.headers).responseJSON { (response) in
                if response.result.isSuccess {
                    let discussionResponse = JSON(response.value as Any)
                    print(discussionResponse)
                    if discussionResponse["discussions"].count == 0 {
                        completion()
                    } else {
                        for i in 0 ..< discussionResponse["discussions"].count {
                            let discussion = Discussion()
                            discussion.name = discussionResponse["discussions"][i]["name"].string ?? "No Name"
                            discussion.author = discussionResponse["discussions"][i]["userfullname"].string?.capitalized ?? ""
                            discussion.date = discussionResponse["discussions"][i]["created"].int!
                            discussion.message = discussionResponse["discussions"][i]["message"].string ?? "No Content"
                            discussion.id = discussionResponse["discussions"][i]["id"].int!
                            discussion.moduleId = self.currentModule.id
                            if discussionResponse["discussions"][i]["attachment"].string! != "0" {
                                if discussionResponse["discussions"][i]["attachments"][0]["fileurl"].string?.contains("td.bits-hyderabad.ac.in") ?? false {
                                    discussion.attachment = discussionResponse["discussions"][i]["attachments"][0]["fileurl"].string! + "?&token=\(KeychainWrapper.standard.string(forKey: "userPassword")!)"
                                } else {
                                    discussion.attachment = discussionResponse["discussions"][i]["attachments"][0]["fileurl"].string ?? ""
                                }
                                
                                discussion.filename = discussionResponse["discussions"][i]["attachments"][0]["filename"].string ?? ""
                                discussion.mimetype = discussionResponse["discussions"][i]["attachments"][0]["mimetype"].string ?? ""
                            }
                            let realm = try! Realm()
                            try! realm.write {
                                realm.add(discussion, update: .modified)
                            }
                            
                            self.discussionArray.append(discussion)
                        }
                        completion()
                    }
                }
            }
        } else {
            let realm = try! Realm()
            let realmDiscussions = realm.objects(Discussion.self).filter("moduleId = %@", self.currentModule.id)
            self.discussionArray.removeAll()
            for i in 0..<realmDiscussions.count {
                discussionArray.append(realmDiscussions[i])
            }
        }
        
        
    }
    
    func canAddDiscussion() {
        let params : [String : String] = ["wstoken" : KeychainWrapper.standard.string(forKey: "userPassword")!, "forumid" : String(currentModule.id)]
        let headers = constants.headers
        let FINAL_URL = constants.BASE_URL + constants.CAN_ADD_DISCUSSIONS
        
        Alamofire.request(FINAL_URL, method: .get, parameters: params, headers: headers).responseJSON { (response) in
            if response.result.isSuccess {
                let canAdd = JSON(response.value as Any)
                if canAdd["status"].bool == false {
                    self.addDiscussionButton.tintColor = UIColor.clear
                    self.addDiscussionButton.style = .plain
                    self.addDiscussionButton.isEnabled = false
                } else {
                    self.addDiscussionButton.isEnabled = true
                }
            }
        }
    }
    @IBAction func addDiscussionButtonPressed(_ sender: Any) {
        performSegue(withIdentifier: "goToAddDiscussion", sender: self)
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
}

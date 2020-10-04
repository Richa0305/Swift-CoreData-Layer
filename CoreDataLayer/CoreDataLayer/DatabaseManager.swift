//
//  DatabaseManager.swift
//  CoreDataLayer
//
//  Created by Richa Srivastava on 04/10/20.
//  Copyright © 2020 Richa Srivastava. All rights reserved.
//

import UIKit
import CoreData

class DatabaseManager {
    
    //MARK: - Swift Singleton initialization
    static var sharedInstance: DatabaseManager = DatabaseManager()
    
    var dataBaseQueue: DispatchQueue = DispatchQueue(label: "com.harsivo.databaseQueue")
    
    var persistentStoreCoordinator: NSPersistentStoreCoordinator
    
    // MARK: Properties
    static let storeFileName = "CoreDataLayer.sqlite"
    
    // The managed object model
    static let managedObjectModel: NSManagedObjectModel = { () -> NSManagedObjectModel in
        let modelURL = Bundle.main.url(forResource: "CoreDataLayer", withExtension: "momd")
        return NSManagedObjectModel(contentsOf: modelURL!)!
    }()
    
    private init() {
        self.persistentStoreCoordinator = DatabaseManager.getPersistanceStoreCoordinator()
    }
    
    static func getPersistanceStoreCoordinatorOptions() -> [AnyHashable: Any] {
        return [
            NSMigratePersistentStoresAutomaticallyOption: true, /* Key to automatically attempt to migrate versioned stores. */
            NSInferMappingModelAutomaticallyOption: true /* Key to attempt to create the mapping model automatically. */
        ]
    }
    static func getPersistanceStoreCoordinator() -> NSPersistentStoreCoordinator {
        // This implementation creates and return a coordinator, having added the store for the application to it.
        let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: DatabaseManager.managedObjectModel)
        do {
            try persistentStoreCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: DatabaseManager.storeURL, options: DatabaseManager.getPersistanceStoreCoordinatorOptions())
        } catch {
            fatalError("Could not add the persistent store: \(error).")
        }
        return persistentStoreCoordinator
    }
    
    /// The directory the application uses to store the Core Data store file.
    static let applicationDocumentsDirectory: URL = {
        // The directory the application uses to store the Core Data store file. This code uses a directory named "com.cocoacasts.PersistentStores" in the application's documents Application Support directory.
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return urls[urls.count-1]
    }()
    
    /// URL for the main Core Data store file.
    static let storeURL: URL = {
        return DatabaseManager.applicationDocumentsDirectory.appendingPathComponent(storeFileName)
    }()
    
    // The context that has the direct access to persistent store coordinator
    lazy var parentContext: NSManagedObjectContext = { () -> NSManagedObjectContext in
        let parentContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        parentContext.persistentStoreCoordinator = DatabaseManager.sharedInstance.persistentStoreCoordinator
        parentContext.undoManager = nil
        parentContext.retainsRegisteredObjects = true
        return parentContext
    }()
    
    // The context which can be used by UI. However utilizing this context will block the caller thread.
    lazy var mainContext: NSManagedObjectContext = { () -> NSManagedObjectContext in
        let mainContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        mainContext.parent = self.parentContext
        mainContext.undoManager = nil
        mainContext.retainsRegisteredObjects = true
        return mainContext
    }()
    
    // The context which can be used by any thread. Utilizing this context will not block the caller thread.
    lazy var childContext: NSManagedObjectContext = { () -> NSManagedObjectContext in
        let childContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        childContext.parent = self.mainContext
        childContext.undoManager = nil
        childContext.retainsRegisteredObjects = true
        return childContext
    }()
    
    func saveContextSynchronously(_ managedObjectContext: NSManagedObjectContext, completionBlock: ((Bool) -> Void)? = nil) {
        managedObjectContext.performAndWait({ () -> Void in
            if managedObjectContext.hasChanges {
                
                do {
                    try managedObjectContext.save()
                    
                    // Check whether present context has associated with the parent context
                    if managedObjectContext.parent != nil {
                        // Do recursive call back
                        self.saveContextSynchronously(managedObjectContext.parent!, completionBlock: completionBlock)
                    } else {
                        completionBlock?(true)
                    }
                    
                } catch let error as NSError {
                    // Oops, something went wrong.
                    completionBlock?(false)
                }
                
            } else {
                completionBlock?(true)
            }
        })
    }
    
    func saveContext(_ managedObjectContext: NSManagedObjectContext, completionBlock: ((Bool) -> Void)? = nil) {
        
        if managedObjectContext.hasChanges {
            managedObjectContext.perform { () -> Void in
                do {
                    try managedObjectContext.save()
                    if managedObjectContext.parent != nil {
                        self.saveContext(managedObjectContext.parent!, completionBlock: completionBlock)
                    } else {
                        completionBlock?(true)
                    }
                } catch let error as NSError {
                    // Oops, something went wrong.
                   
                    completionBlock?(false)
                }
            }
        } else {
            completionBlock?(true)
        }
        
    }
    
    // Clean
    deinit {
        // Returns all the contexts to its base state
        self.childContext.reset()
        self.parentContext.reset()
        self.mainContext.reset()
        
        // Disable/Remove cookies
        if let cookies = HTTPCookieStorage.shared.cookies {
            for (_, cookie) in cookies.enumerated() {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        
        let storeURL = DatabaseManager.storeURL
        do {
            try FileManager.default.removeItem(at: storeURL)
        } catch {

            // Oops, something went wrong.
        }
    }
    
    //MARK:
    
    func deleteObjects(_ objects: [NSManagedObject], context: NSManagedObjectContext, save: Bool = true) {
        // Get context based on parameter
        for eachObject in objects {
            if eachObject.managedObjectContext == context {
                context.delete(eachObject)
            }
        }
        if save {
            saveContext(context, completionBlock: nil)
        }
    }
    
 
    func destroyPersistanceStore(completionHandler: () -> Void) {
        do {
            self.childContext.reset()
            self.mainContext.reset()
            self.parentContext.reset()
            try self.persistentStoreCoordinator.destroyPersistentStore(at: DatabaseManager.storeURL, ofType: NSSQLiteStoreType, options: DatabaseManager.getPersistanceStoreCoordinatorOptions())
            try self.persistentStoreCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: DatabaseManager.storeURL, options: DatabaseManager.getPersistanceStoreCoordinatorOptions())
            completionHandler()
        } catch {
            
            DatabaseManager.reInitSharedInstance()
            completionHandler()
        }
    }
    static func reInitSharedInstance() {
        DatabaseManager.sharedInstance = DatabaseManager()
    }
}

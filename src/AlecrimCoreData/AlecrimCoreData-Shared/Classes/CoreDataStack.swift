//
//  CoreDataStack.swift
//  AlecrimCoreData
//
//  Created by Vanderlei Martinelli on 2014-06-24.
//  Copyright (c) 2014 Alecrim. All rights reserved.
//

import Foundation
import CoreData

internal class CoreDataStack {
    
    private let model: NSManagedObjectModel
    private let coordinator: NSPersistentStoreCoordinator
    private let store: NSPersistentStore
    
    private let savingContext: NSManagedObjectContext
    internal let mainContext: NSManagedObjectContext
    
    internal init(modelName name: NSString?) {
        let bundle = NSBundle.mainBundle()
        let modelName: NSString = (name == nil ? (bundle.infoDictionary[kCFBundleNameKey] as? NSString)! : name!)
        let modelURL = bundle.URLForResource(modelName, withExtension: "momd")
        
        let fileManager = NSFileManager.defaultManager()
        let urls = fileManager.URLsForDirectory(.ApplicationSupportDirectory, inDomains: .UserDomainMask)
        let applicationSupportDirectoryURL = urls[urls.endIndex - 1] as NSURL

        let localStoreDirectoryURL = applicationSupportDirectoryURL.URLByAppendingPathComponent(bundle.bundleIdentifier, isDirectory: true)
        if !fileManager.fileExistsAtPath(localStoreDirectoryURL.absoluteString) {
            fileManager.createDirectoryAtURL(localStoreDirectoryURL, withIntermediateDirectories: true, attributes: nil, error: nil)
        }

        let storeFilename = modelName.stringByAppendingPathExtension("sqlite")
        let localStoreFileURL = localStoreDirectoryURL.URLByAppendingPathComponent(storeFilename, isDirectory: false)
        
        self.model = NSManagedObjectModel(contentsOfURL: modelURL)
        self.coordinator = NSPersistentStoreCoordinator(managedObjectModel: self.model)
        self.store = self.coordinator.addPersistentStoreWithType(NSSQLiteStoreType, configuration: nil, URL: localStoreFileURL, options: nil, error: nil)
        
        self.savingContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        self.savingContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.savingContext.persistentStoreCoordinator = self.coordinator
        self.savingContext.undoManager = nil
        
        self.mainContext = NSManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
        self.mainContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.mainContext.parentContext = self.savingContext
    }
    
}

extension CoreDataStack {

    internal func saveContext(context: NSManagedObjectContext) -> (Bool, NSError?) {
        var currentContext: NSManagedObjectContext? = context
        
        var success = false
        var error: NSError? = nil
        
        while let c = currentContext {
            c.performBlockAndWait {
                success = c.save(&error)
            }
            
            if (!success) {
                break
            }
            
            currentContext = currentContext?.parentContext
        }
        
        return (success, error)
    }
    
    internal func saveContext(context: NSManagedObjectContext, completion: ((Bool, NSError?) -> ())?) {
        context.performBlock {
            var success = false
            var error: NSError? = nil
            
            success = context.save(&error)
            
            if success {
                if let parentContext = context.parentContext {
                    self.saveContext(parentContext, completion: completion)
                }
                else {
                    completion?(true, nil)
                }
            }
            else {
                completion?(false, error)
            }
        }
    }

}

extension CoreDataStack {
    
    internal func createBackgroundContext() -> NSManagedObjectContext {
        return CoreDataStackBackgroundManagedObjectContext(savingContext: self.savingContext, mainContext: self.mainContext)
    }
    
}

private class CoreDataStackBackgroundManagedObjectContext: NSManagedObjectContext {
    
    private let mainContext: NSManagedObjectContext
    
    private init(savingContext: NSManagedObjectContext, mainContext: NSManagedObjectContext) {
        self.mainContext = mainContext
        
        super.init(concurrencyType: .PrivateQueueConcurrencyType)
        
        self.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.parentContext = savingContext
        self.undoManager = nil
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("backgroundManagedObjectContextDidSave:"), name: NSManagedObjectContextDidSaveNotification, object: self)
    }
    
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self, name: NSManagedObjectContextDidSaveNotification, object: self)
    }
    
    @objc private func backgroundManagedObjectContextDidSave(notification: NSNotification) {
        self.mainContext.performBlock {
            self.mainContext.mergeChangesFromContextDidSaveNotification(notification)
        }
    }
    
}

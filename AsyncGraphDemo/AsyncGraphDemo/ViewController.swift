//
//  ViewController.swift
//  AsyncGraphDemo
//
//  Created by Boolky Bear on 2/12/14.
//  Copyright (c) 2014 ByBDesigns. All rights reserved.
//

import UIKit

enum Entity: String
{
	case Person = "Person"
	case PersonData = "Person data"
	case PersonValues = "Person values"
	case Unrelated = "Unrelated data"
}

enum Operation: Int
{
	case Commit = 0
	case Update = 1
}

class ViewController: UIViewController {

	@IBOutlet var outputTextView: UITextView!
	
	var messages = [String]()
	
	override func viewDidLoad() {
		super.viewDidLoad()
		// Do any additional setup after loading the view, typically from a nib.
		
		self.asyncGraphDemo();
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}

	func asyncGraphDemo()
	{		
		let graph = AsyncGraph(builder: GraphDefinitionBuilder()
			.addNode(Entity.Person.rawValue, tag: Operation.Update.rawValue)
			.addNode(Entity.Person.rawValue, tag: Operation.Commit.rawValue)
			.addNode(Entity.PersonData.rawValue, tag: Operation.Update.rawValue)
			.addNode(Entity.PersonData.rawValue, tag: Operation.Commit.rawValue)
			.addNode(Entity.Unrelated.rawValue, tag: Operation.Update.rawValue)
			.addNode(Entity.PersonValues.rawValue, tag: Operation.Update.rawValue)
			.addDependency(Entity.Person.rawValue, fromTag: Operation.Update.rawValue, toIdentifier: Entity.Person.rawValue, toTag: Operation.Commit.rawValue)
			.addDependency(Entity.PersonData.rawValue, fromTag: Operation.Commit.rawValue, toIdentifier: Entity.Person.rawValue, toTag: Operation.Update.rawValue)
			.addDependency(Entity.PersonValues.rawValue, fromTag: Operation.Update.rawValue, toIdentifier: Entity.Person.rawValue, toTag: Operation.Update.rawValue)
			.addDependency(Entity.PersonData.rawValue, fromTag: Operation.Update.rawValue, toIdentifier: Entity.PersonData.rawValue, toTag: Operation.Commit.rawValue)
			.addDependency(Entity.PersonData.rawValue, fromTag: Operation.Update.rawValue, toIdentifier: Entity.Person.rawValue, toTag: Operation.Commit.rawValue))
		
		srand(UInt32(time(nil)))
		let operationValues = [ "commit", "update" ];
		
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
			self.appendMessage("Processing graph")
			graph.process() {
				nodeIdentifier in
				
				let operation = operationValues[nodeIdentifier.tag!]
				
				let delay = (rand() & 0x7) + 1
				
				self.appendMessage("Processing \(nodeIdentifier.identifier) - \(operation) (\(delay) seconds)")
				
				NSThread.sleepForTimeInterval(NSTimeInterval(delay))
				
				self.appendMessage("Processed \(nodeIdentifier.identifier) - \(operation)")
				
				return nil
			}
			self.appendMessage("Processed graph")
		}
	}
	
	func appendMessage(message: String)
	{
		dispatch_async(dispatch_get_main_queue()) {
			self.messages.append(message)
			
			self.outputTextView.text = join("\n", self.messages)
		}
	}
}


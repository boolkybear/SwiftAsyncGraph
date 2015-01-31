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
		let personUpdate = NodeIdentifier(Entity.Person.rawValue, Operation.Update.rawValue)
		let personCommit = NodeIdentifier(Entity.Person.rawValue, Operation.Commit.rawValue)
		let personDataUpdate = NodeIdentifier(Entity.PersonData.rawValue, Operation.Update.rawValue)
		let personDataCommit = NodeIdentifier(Entity.PersonData.rawValue, Operation.Commit.rawValue)
		let unrelatedUpdate = NodeIdentifier(Entity.Unrelated.rawValue, Operation.Update.rawValue)
		let personValuesUpdate = NodeIdentifier(Entity.PersonValues.rawValue, Operation.Update.rawValue)
		
		let graph = AsyncGraph(GraphDefinition(nodes: [	NodeDefinition(personUpdate),
														NodeDefinition(personCommit),
														NodeDefinition(personDataUpdate, true),
														NodeDefinition(personDataCommit),
														NodeDefinition(unrelatedUpdate),
														NodeDefinition(personValuesUpdate) ],
			dependencies: [	DependencyDefinition(from: personUpdate, to: personCommit),
							DependencyDefinition(from: personDataCommit, to: personUpdate),
							DependencyDefinition(from: personValuesUpdate, to: personUpdate),
							DependencyDefinition(from: personDataUpdate, to: personDataCommit, personCommit) ]))
		
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


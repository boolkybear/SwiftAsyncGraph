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
	
	func toString() -> String {
		switch self
		{
		case .Commit:
			return "commit"
			
		case .Update:
			return "update"
		}
	}
}

struct NodeIdentifier: Hashable
{
	let entity: Entity
	let operation: Operation?
	
	func toString() -> String {
		let operationStr = self.operation.map { $0.toString() } ?? "null"

		return "\(self.entity.rawValue) - \(operationStr)"
	}
	
	var hashValue: Int {
		return self.toString().hashValue
	}
}

func == (lhs: NodeIdentifier, rhs: NodeIdentifier) -> Bool {
	return lhs.entity == rhs.entity && lhs.operation == rhs.operation
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
		let personUpdate = NodeIdentifier(entity: .Person, operation: .Update)
		let personCommit = NodeIdentifier(entity: .Person, operation: .Commit)
		let personDataUpdate = NodeIdentifier(entity: .PersonData, operation: .Update)
		let personDataCommit = NodeIdentifier(entity: .PersonData, operation: .Commit)
		let unrelatedUpdate = NodeIdentifier(entity: .Unrelated, operation: .Update)
		let personValuesUpdate = NodeIdentifier(entity: .PersonValues, operation: .Update)
		
		let graph = AsyncGraph<NodeIdentifier, Void> {
			identifier, operation, graph in
			
			let delay = (rand() & 0x7) + 1
			
			self.appendMessage("Processing \(identifier.toString()) (\(delay) seconds)")
			
			NSThread.sleepForTimeInterval(NSTimeInterval(delay))
			
			self.appendMessage("Processed \(identifier.toString())")
		}
			.addNodeWithIdentifier(personUpdate)
			.addNodeWithIdentifier(personCommit)
			.addNodeWithIdentifier(personDataUpdate)
			.addNodeWithIdentifier(personDataCommit)
			.addNodeWithIdentifier(unrelatedUpdate)
			.addNodeWithIdentifier(personValuesUpdate)
			.addDependencyFrom(personUpdate, to: personCommit)
			.addDependencyFrom(personDataCommit, to: personUpdate)
			.addDependencyFrom(personValuesUpdate, to: personUpdate)
			.addDependencyFrom(personDataUpdate, to: personDataCommit)
			.addDependencyFrom(personDataUpdate, to: personCommit)
		
		srand(UInt32(time(nil)))
		
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
			self.appendMessage("Processing graph")
			graph.processSynchronous()
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


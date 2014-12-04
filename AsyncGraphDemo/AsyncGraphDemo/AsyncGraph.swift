//
//  AsyncGraph.swift
//  AsyncGraph
//
//  Created by Boolky Bear on 23/11/14.
//  Copyright (c) 2014 ByBDesigns. All rights reserved.
//

import Foundation

enum AsyncGraphStatus
{
	case Initialized
	case Waiting
	case Processing
	case Processed
	case Cancelled
}

struct NodeIdentifier: Hashable
{
	let identifier: String
	let tag: Int? = nil
	
	init (_ identifier: String, _ tag: Int? = nil)
	{
		self.identifier = identifier
		self.tag = tag
	}
	
	var hashValue: Int
	{
		var tagStr = "tag = (null)"
		if let tagValue = self.tag
		{
			tagStr = "tag = \(tagValue)"
		}
		let fullStr = "identifier = \(self.identifier); \(tagStr)"
		
		return fullStr.hashValue
	}
}

struct NodeDefinition
{
	let identifier: NodeIdentifier
	let isConcurrent: Bool = true
	
	init(_ identifier: String, _ tag: Int? = nil, _ isConcurrent: Bool = true)
	{
		self.init(NodeIdentifier(identifier, tag), isConcurrent)
	}
	
	init(_ identifier: NodeIdentifier, _ isConcurrent: Bool = true)
	{
		self.identifier = identifier
		self.isConcurrent = isConcurrent
	}
}

struct DependencyDefinition
{
	let from: NodeIdentifier
	let to: [NodeIdentifier]
	
	init(from: NodeIdentifier, to: NodeIdentifier...)
	{
		var parents = [NodeIdentifier]()
		for parent in to
		{
			parents.append(parent)
		}
		
		self.from = from
		self.to = parents
	}
}

struct GraphDefinition
{
	let nodes: [NodeDefinition]
	let dependencies: [DependencyDefinition]
}

func ==(lhs: NodeIdentifier, rhs: NodeIdentifier) -> Bool
{
	return lhs.identifier == rhs.identifier && lhs.tag == rhs.tag
}

class AsyncGraph
{
	typealias NodeResult = Any
	typealias NodeProcessor = (NodeIdentifier) -> NodeResult?
	
	private class AsyncGraphNode
	{
		let identifier: NodeIdentifier
		let isConcurrent: Bool
		
		private let semaphore: dispatch_semaphore_t
		
		private var parentNodes: [AsyncGraphNode]
		private var dependantNodes: [AsyncGraphNode]
		
		private var privateStatus: AsyncGraphStatus
		var status: AsyncGraphStatus { get { return self.privateStatus } }
		
		private var privateResult: NodeResult?
		var result: NodeResult? { get { return self.privateResult } }
		
		required init(_ definition: NodeDefinition)
		{
			self.identifier = definition.identifier
			self.isConcurrent = definition.isConcurrent
			
			self.semaphore = dispatch_semaphore_create(1);
			
			self.parentNodes = [AsyncGraphNode]()
			self.dependantNodes = [AsyncGraphNode]()
			
			self.privateResult = nil
			self.privateStatus = .Initialized
		}
		
		func addParentNode(node: AsyncGraphNode)
		{
			if self.status == .Initialized || self.status == .Waiting
			{
				self.parentNodes.append(node)
			}
		}
		
		func addDependantNode(node: AsyncGraphNode)
		{
			if self.status == .Initialized || self.status == .Waiting
			{
				self.dependantNodes.append(node)
			}
		}
		
		func process(graph: AsyncGraph, processor: NodeProcessor)
		{
			self.privateStatus = .Waiting
			
			for i in 0...self.parentNodes.count
			{
				dispatch_semaphore_wait(self.semaphore, DISPATCH_TIME_FOREVER)
			}
			
			self.privateStatus = .Processing
			graph.didStartProcessingNodeConcurrent(self.isConcurrent)
			
			if graph.isCancelled() == false
			{
				self.privateResult = processor(self.identifier)
			}
			
			self.privateStatus = .Processed
			graph.didEndProcessingNodeConcurrent(self.isConcurrent)
			
			for childNode in self.dependantNodes
			{
				dispatch_semaphore_signal(childNode.semaphore);
			}
			
			dispatch_semaphore_signal(self.semaphore);
		}
	}
	
	private var nodeDictionary: [ NodeIdentifier : AsyncGraphNode ]
	
	private var concurrentProcessCount: Int
	private var nonConcurrentProcessCount: Int
	private var concurrentSemaphore: dispatch_semaphore_t
	private var nonConcurrentSemaphore: dispatch_semaphore_t
	private var concurrentQueue: dispatch_queue_t
	private var nonConcurrentQueue: dispatch_queue_t
	private var mutexQueue: dispatch_queue_t
	
	private var privateStatus: AsyncGraphStatus
	var status: AsyncGraphStatus { get { return self.privateStatus } }
	
	init(_ definition: GraphDefinition?)
	{
		self.concurrentProcessCount = 0
		self.nonConcurrentProcessCount = 0
		self.concurrentSemaphore = dispatch_semaphore_create(1)
		self.nonConcurrentSemaphore = dispatch_semaphore_create(1)
		self.concurrentQueue = dispatch_queue_create("com.bybdesigns.asyncgraph.concurrentQueue", DISPATCH_QUEUE_SERIAL)
		self.nonConcurrentQueue = dispatch_queue_create("com.bybdesigns.asyncgraph.nonConcurrentQueue", DISPATCH_QUEUE_SERIAL)
		self.mutexQueue = dispatch_queue_create("com.bybdesigns.asyncgraph.mutexQueue", DISPATCH_QUEUE_SERIAL)
		self.privateStatus = .Initialized
	
		self.nodeDictionary = [ NodeIdentifier : AsyncGraphNode ]()
	
		if let graphDefinition = definition
		{
			for nodeDefinition in graphDefinition.nodes
			{
				self.addNodeWithDefinition(nodeDefinition)
			}
			
			for dependencyDefinition in graphDefinition.dependencies
			{
				let from = dependencyDefinition.from
				
				for to in dependencyDefinition.to
				{
					self.addDependencyFrom(from, to: to)
				}
			}
		}
	}
	
	convenience init()
	{
		self.init(nil)
	}
	
	func addNodeWithDefinition(definition: NodeDefinition)
	{
		if self.status == .Initialized
		{
			let node = self.nodeDictionary[definition.identifier]
			if node == nil
			{
				let nodeToAdd = AsyncGraphNode(definition)
				self.nodeDictionary.updateValue(nodeToAdd, forKey:definition.identifier)
			}
		}
	}
	
	func addDependencyFrom(from: NodeIdentifier, to: NodeIdentifier)
	{
		if self.status == .Initialized
		{
			let fromNode = self.nodeDictionary[from]
			let toNode = self.nodeDictionary[to]
			
			if let from = fromNode
			{
				if let to = toNode
				{
					from.addParentNode(to)
					to.addDependantNode(from)
				}
			}
		}
	}
	
	func process(processor: NodeProcessor)
	{
		self.privateStatus = .Processing
	
		let graphGroup = dispatch_group_create();
	
		let keys = self.nodeDictionary.keys
		for key in keys
		{
			let node = self.nodeDictionary[key]!
	
			dispatch_group_async(graphGroup, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
				[unowned self] in
				node.process(self, processor)
			}
		}
		
		dispatch_group_wait(graphGroup, DISPATCH_TIME_FOREVER);
	
		if self.status == .Processing
		{
			self.privateStatus = .Processed
		}
	}
	
	func resultFromNode(identifier: NodeIdentifier) -> NodeResult?
	{
		return self.nodeDictionary[identifier]?.result
	}
	
	func didStartProcessingNodeConcurrent(isConcurrent: Bool)
	{
		if isConcurrent		// concurrent access (reader)
		{
			dispatch_sync(self.mutexQueue) {
				dispatch_semaphore_wait(self.concurrentSemaphore, DISPATCH_TIME_FOREVER);
				
				dispatch_sync(self.concurrentQueue) {
					++self.concurrentProcessCount;
					if self.concurrentProcessCount == 1
					{
						dispatch_semaphore_wait(self.nonConcurrentSemaphore, DISPATCH_TIME_FOREVER);
					}
				}
				
				dispatch_semaphore_signal(self.concurrentSemaphore);
			}
		}
		else				// non concurrent access (writer)
		{
			dispatch_sync(self.nonConcurrentQueue) {
				++self.nonConcurrentProcessCount
				if self.nonConcurrentProcessCount == 1
				{
					dispatch_semaphore_wait(self.concurrentSemaphore, DISPATCH_TIME_FOREVER);
				}
			}
	
			dispatch_semaphore_wait(self.nonConcurrentSemaphore, DISPATCH_TIME_FOREVER);
		}
	}
	
	func didEndProcessingNodeConcurrent(isConcurrent: Bool)
	{
		if isConcurrent		// concurrent access (reader)
		{
			dispatch_sync(self.concurrentQueue) {
				--self.concurrentProcessCount
				if self.concurrentProcessCount == 0
				{
					dispatch_semaphore_signal(self.nonConcurrentSemaphore)
				}
			}
		}
		else				// non concurrent access (writer)
		{
			dispatch_semaphore_signal(self.nonConcurrentSemaphore)
	
			dispatch_sync(self.nonConcurrentQueue) {
				--self.nonConcurrentProcessCount;
				if self.nonConcurrentProcessCount == 0
				{
					dispatch_semaphore_signal(self.concurrentSemaphore)
				}
			}
		}
	}
	
	func cancel()
	{
		self.privateStatus = .Cancelled
	}
	
	func isCancelled() -> Bool
	{
		return (self.status == .Cancelled)
	}
}
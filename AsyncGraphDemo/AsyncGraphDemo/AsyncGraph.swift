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
	case Initializing
	case Processing
	case Cancelled
	case Paused
	case Processed
}

private struct AsyncGraphNodeDefinition<NodeIdentifier: Hashable, NodeResult>
{
	typealias NodeOperation = (NodeIdentifier, NSOperation, AsyncGraph<NodeIdentifier, NodeResult>) -> NodeResult
	
	let identifier: NodeIdentifier
	let isConcurrent: Bool
	let operation: NodeOperation?
}

class AsyncGraph<NodeIdentifier: Hashable, NodeResult> {
	typealias NodeOperation = (NodeIdentifier, NSOperation, AsyncGraph<NodeIdentifier, NodeResult>) -> NodeResult
	typealias NodeHook = (NodeIdentifier, NSOperation, AsyncGraph<NodeIdentifier, NodeResult>) -> Void
	typealias GraphHook = (AsyncGraph<NodeIdentifier, NodeResult>) -> Void
	
	private var operationQueue: NSOperationQueue? = nil
	
	private var nodes: [ NodeIdentifier : AsyncGraphNodeDefinition<NodeIdentifier, NodeResult> ]
	private var dependencies: [ NodeIdentifier : Set<NodeIdentifier> ]
	private var results: [ NodeIdentifier : NodeResult ]
	
	private var defaultOperation: NodeOperation?
	
	private (set) var status: AsyncGraphStatus
	
	private var hooksBefore: [ NodeIdentifier : [NodeHook] ]
	private var hooksAfter: [ NodeIdentifier : [NodeHook] ]
	private var graphHooks: [ GraphHook ]
	
	// Concurrency
	private var concurrentProcessCount: Int
	private var nonConcurrentProcessCount: Int
	private var concurrentSemaphore: dispatch_semaphore_t
	private var nonConcurrentSemaphore: dispatch_semaphore_t
	private var concurrentQueue: dispatch_queue_t
	private var nonConcurrentQueue: dispatch_queue_t
	private var mutexQueue: dispatch_queue_t
	
	init(defaultOperation: NodeOperation? = nil)
	{
		self.operationQueue = nil
		self.nodes = [ NodeIdentifier : AsyncGraphNodeDefinition<NodeIdentifier, NodeResult> ]()
		self.dependencies = [ NodeIdentifier : Set<NodeIdentifier> ]()
		self.results = [ NodeIdentifier : NodeResult ]()
		
		self.defaultOperation = defaultOperation
		self.status = AsyncGraphStatus.Initializing
		
		self.hooksBefore = [ NodeIdentifier : [NodeHook] ]()
		self.hooksAfter = [ NodeIdentifier : [NodeHook] ]()
		self.graphHooks = [ GraphHook ]()
		
		// Concurrency
		self.concurrentProcessCount = 0
		self.nonConcurrentProcessCount = 0
		self.concurrentSemaphore = dispatch_semaphore_create(1)
		self.nonConcurrentSemaphore = dispatch_semaphore_create(1)
		self.concurrentQueue = dispatch_queue_create("com.bybdesigns.asyncgraph.concurrentQueue", DISPATCH_QUEUE_SERIAL)
		self.nonConcurrentQueue = dispatch_queue_create("com.bybdesigns.asyncgraph.nonConcurrentQueue", DISPATCH_QUEUE_SERIAL)
		self.mutexQueue = dispatch_queue_create("com.bybdesigns.asyncgraph.mutexQueue", DISPATCH_QUEUE_SERIAL)
	}
	
	func addNodeWithIdentifier(identifier: NodeIdentifier, isConcurrent: Bool = true, operation: NodeOperation? = nil) -> AsyncGraph
	{
		if let duplicatedNode = self.nodes[identifier]
		{
			NSLog("Not adding \(identifier) to the graph, as it already exists")
		}
		else
		{
			self.nodes[identifier] = AsyncGraphNodeDefinition(identifier: identifier, isConcurrent: isConcurrent, operation: operation)
		}
		
		return self
	}
	
	func addDependencyFrom(identifier: NodeIdentifier, to: NodeIdentifier) -> AsyncGraph
	{
		return addDependencyFrom(identifier, toNodes: [to])
	}
	
	func addDependencyFrom(identifier: NodeIdentifier, toNodes: [NodeIdentifier]) -> AsyncGraph
	{
		let parents = self.dependencies[identifier] ?? Set<NodeIdentifier>()
		self.dependencies[identifier] = parents.union(toNodes)
		
		return self
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
	
	func fireHooks(hooks: [ NodeHook ]?, identifier: NodeIdentifier, operation: NSOperation, graph: AsyncGraph<NodeIdentifier, NodeResult>)
	{
		if let hooks = hooks
		{
			for hook in hooks
			{
				hook(identifier, operation, self)
			}
		}
	}
	
	func operations() -> [ NSOperation ]
	{
		var operations = [ NodeIdentifier : NSOperation ]()
		
		for (identifier, node) in self.nodes
		{
			let operation = NSBlockOperation()
			operation.addExecutionBlock() {
				[unowned operation] in
				
				self.didStartProcessingNodeConcurrent(node.isConcurrent)
				self.fireHooks(self.hooksBefore[identifier], identifier: identifier, operation: operation, graph: self)
				
				let result = node.operation?(node.identifier, operation, self) ?? self.defaultOperation?(node.identifier, operation, self)
				self.results[identifier] = result
				
				self.fireHooks(self.hooksAfter[identifier], identifier: identifier, operation: operation, graph: self)
				self.didEndProcessingNodeConcurrent(node.isConcurrent)
			}
			
			operations[identifier] = operation
		}
		
		for (identifier, dependencies) in self.dependencies
		{
			if let operation = operations[identifier]
			{
				for dependency in dependencies
				{
					if let dependency = operations[dependency]
					{
						operation.addDependency(dependency)
					}
				}
			}
		}
		
		return operations.values.array
	}
	
	func resultFrom(identifier: NodeIdentifier) -> NodeResult?
	{
		return self.results[identifier]
	}
	
	private func markAsProcessedAndFireHooks()
	{
		self.status = self.status == .Cancelled ? .Cancelled : .Processed
		
		for hook in self.graphHooks
		{
			hook(self)
		}
	}
	
	private func processAndWaitUntilFinished(waitUntilFinished: Bool)
	{
		if(self.status == .Initializing)
		{
			self.status = .Processing
			
			let operations = self.operations()
			
			if(waitUntilFinished)
			{
				let operationQueue = NSOperationQueue()
				operationQueue.addOperations(operations, waitUntilFinished: true)
				
				self.markAsProcessedAndFireHooks()
			}
			else
			{
				self.operationQueue = NSOperationQueue()
				self.operationQueue?.addOperations(operations, waitUntilFinished: false)
				
				dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)) {
					self.operationQueue?.waitUntilAllOperationsAreFinished()
					
					self.markAsProcessedAndFireHooks()
				}
			}
		}
	}
	
	func processSynchronous()
	{
		self.processAndWaitUntilFinished(true)
	}
	
	func process() -> AsyncGraph<NodeIdentifier, NodeResult>
	{
		self.processAndWaitUntilFinished(false)
		
		return self
	}
	
	func pause()
	{
		if(self.status == .Processing)
		{
			self.status = .Paused
			
			self.operationQueue?.suspended = true
		}
	}
	
	func resume()
	{
		if(self.status == .Paused)
		{
			self.status = .Processing
			
			self.operationQueue?.suspended = false
		}
	}
	
	func cancel()
	{
		switch self.status
		{
		case .Processing: fallthrough
		case .Paused:
			self.operationQueue?.cancelAllOperations()
			self.operationQueue?.suspended = false
			
			self.operationQueue?.waitUntilAllOperationsAreFinished()
			
			self.status = .Cancelled
			
		default:
			break
		}
	}
	
	func addHookBefore(identifier: NodeIdentifier, hook: NodeHook) -> AsyncGraph
	{
		if var hooks = self.hooksBefore[identifier]
		{
			hooks.append(hook)
			self.hooksBefore[identifier] = hooks
		}
		else
		{
			self.hooksBefore[identifier] = [ hook ]
		}
		
		return self
	}
	
	func addHookAfter(identifier: NodeIdentifier, hook: NodeHook) -> AsyncGraph
	{
		if var hooks = self.hooksAfter[identifier]
		{
			hooks.append(hook)
			self.hooksAfter[identifier] = hooks
		}
		else
		{
			self.hooksAfter[identifier] = [ hook ]
		}
		
		return self
	}
	
	func addHook(hook: GraphHook) -> AsyncGraph
	{
		self.graphHooks.append(hook)
		
		return self
	}
}
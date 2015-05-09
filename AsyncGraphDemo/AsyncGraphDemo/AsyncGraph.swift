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
	
	// MARK: Initialization
	/**
		Graph constructor
	
		:param:	defaultOperation	Optional closure to be executed in case no closure is specified on a node
	*/
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
	
	/**
		Adds a node to the graph. When processing, the code for this node will be executed in an NSOperation
	
		:param:	identifier	Identifier for this node. Can be whatever makes sense for your algorithm, but it must conform to Hashable and Equatable
		:param:	isConcurrent	The default is true. If true, this node will execute concurrently with other nodes.
								If false, the graph will wait for the nodes that are currently executing, then will execute this node exclusively,
								and then will continue executing concurrent nodes. Useful for accessing to critical resources or constrained environments.
		:param:	operation	Closure to execute in this node. If not specified, the closure executed will be the default one specified when creating the graph.
	
		:returns:	The graph itself, allowing for fluent interfaces
	*/
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
	
	/**
		Adds a dependency between nodes. The node identified by identifier won't be processed until the node identified by to has finished processing
	
		:param:	identifier	Identifier of the dependant node
		:param:	to	Identifier of the parent node
	
		:returns:	The graph itself, allowing for fluent interfaces
	*/
	func addDependencyFrom(identifier: NodeIdentifier, to: NodeIdentifier) -> AsyncGraph
	{
		return addDependencyFrom(identifier, toNodes: [to])
	}
	
	/**
		Adds dependencies between nodes. The node identified by identifier won't be processed until all the nodes in toNodes have been processed
		
		:param:	identifier	Identifier of the dependant node
		:param:	toNodes	Identifiers of the parent nodes
		
		:returns:	The graph itself, allowing for fluent interfaces
	*/
	func addDependencyFrom(identifier: NodeIdentifier, toNodes: [NodeIdentifier]) -> AsyncGraph
	{
		let parents = self.dependencies[identifier] ?? Set<NodeIdentifier>()
		self.dependencies[identifier] = parents.union(toNodes)
		
		return self
	}
	
	// MARK: Looking up results
	/**
		Get the result of a node
		
		:param:	identifier	Identifier of the node
	
		:returns:	If the node identified by identifier has been processed and has returned a value from its closure, this method will return that value.
					Otherwise it will return nil
	*/
	func resultFrom(identifier: NodeIdentifier) -> NodeResult?
	{
		return self.results[identifier]
	}
	
	// MARK: Processing
	/**
		Process the graph synchronously. This call blocks the current thread until all nodes have been processed. Processing cannot be paused or cancelled
	*/
	func processSynchronous()
	{
		self.processAndWaitUntilFinished(true)
	}
	
	/**
		Start processing the graph and return immediately, so the current thread is not blocked. Processing can be paused and resumed.
	
		:returns:	The graph itself, allowing for fluent interfaces
	*/
	func process() -> AsyncGraph
	{
		self.processAndWaitUntilFinished(false)
		
		return self
	}
	
	// MARK: Control execution flow
	/**
		Pauses the execution of the current graph. Note that the behavior is defined by the NSOperationQueue: when it is suspended, no operations
		are issued even they are ready to be issued, but the operations that are being executed in this moment, will continue to execute unless
		you check the graph status in your code and pause the operation accordingly.
	*/
	func pause()
	{
		if(self.status == .Processing)
		{
			self.status = .Paused
			
			self.operationQueue?.suspended = true
		}
	}
	
	/**
		Resume the processing. Nodes ready to execute will be issued to the NSOperationQueue
	*/
	func resume()
	{
		if(self.status == .Paused)
		{
			self.status = .Processing
			
			self.operationQueue?.suspended = false
		}
	}
	
	/**
		Cancel the processing.
	*/
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
	
	// MARK: Hooks
	/**
		Add a hook that will be executed when the graph has finished processing. Useful in asynchronous processing
	
		:param:	hook	Closure that will be executed when the graph has finished processing
	
		:returns:	The graph itself, allowing for fluent interfaces
	*/
	func addHook(hook: GraphHook) -> AsyncGraph
	{
		self.graphHooks.append(hook)
		
		return self
	}
	
	/**
		Add a hook that will be executed when the node identified by identifier is about to be executed
		
		:param:	identifier	Identifier of the node
		:param:	hook	Closure that will be executed before the node is executed
		
		:returns:	The graph itself, allowing for fluent interfaces
	*/
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
	
	/**
		Add a hook that will be executed when the node identified by identifier has been executed
		
		:param:	identifier	Identifier of the node
		:param:	hook	Closure that will be executed after the node is executed
		
		:returns:	The graph itself, allowing for fluent interfaces
	*/
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
}

/*
 *	Private helper methods
 */
private extension AsyncGraph {
	
	// MARK: Concurrency
	private func didStartProcessingNodeConcurrent(isConcurrent: Bool)
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
	
	private func didEndProcessingNodeConcurrent(isConcurrent: Bool)
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
	
	// MARK: Processing
	private func operations() -> [ NSOperation ]
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
	
	private func markAsProcessedAndFireHooks()
	{
		self.status = self.status == .Cancelled ? .Cancelled : .Processed
		
		for hook in self.graphHooks
		{
			hook(self)
		}
	}
	
	private func fireHooks(hooks: [ NodeHook ]?, identifier: NodeIdentifier, operation: NSOperation, graph: AsyncGraph<NodeIdentifier, NodeResult>)
	{
		if let hooks = hooks
		{
			for hook in hooks
			{
				hook(identifier, operation, self)
			}
		}
	}
}
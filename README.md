SwiftAsyncGraph
===============

AsyncGraph is a simple graph asynchronous processor, written in Swift. AsyncGraph can help you to simplify synchronization between
asynchronous but related tasks. Each task would be represented as a graph node, and then you would specify dependencies between
tasks. AsyncGraph will process the task nodes, taking care of the dependencies for you. This way, you can focus on writing each
task code and leave synchronization to the graph.

The process function receives a function as parameter. This function will be invoked when a task node is about to be executed,
so you can execute what the node represents, such as downloading content from a webservice or saving CoreData entities.
Although the graph processing is synchronous, each task node will be executed in its own thread and the synchronization will
be accomplished with GCD semaphores. You also have the possibility of defining non-concurrent nodes that will be executed
exclusively, for example for dealing with high memory demand tasks or scarce resources. This has been modelled as [the second
readers-writers problem](https://en.wikipedia.org/wiki/Readers%E2%80%93writers_problem#The_second_readers-writers_problem),
with writer priority, where non-concurrent nodes are writers.

How to use AsyncGraph
---------------------

To use AsyncGraph, simply copy the AsyncGraph.swift file to your project. There is a sample iOS project, AsyncGraphDemo, so
you can see how it works.

In your code, you first create the graph. You can create it initialized or empty, so you can add nodes and dependencies
programmatically. Then you call process(), passing a callback function that will be called for each node. Your callback function
will receive the node identifier as a parameter, so you know which task is going to be executed. You have to be careful to
call process() in a background thread, otherwise it would block the main thread until all nodes are processed. Example:

`` let simpleGraph = AsyncGraph(GraphDefinition(nodes: [NodeDefinition("A"), NodeDefinition("B", 1), NodeDefinition("C", nil, true)],  
			dependencies: [DependencyDefinition(from: NodeIdentifier("B", 1), to: NodeIdentifier("A")),  
				DependencyDefinition(from: NodeIdentifier("C"), to: NodeIdentifier("B", 1))])) ``
				
is equivalent to

`` let simpleGraph = AsyncGraph()  
		simpleGraph.addNodeWithDefinition(NodeDefinition("A"));  
		simpleGraph.addNodeWithDefinition(NodeDefinition("B", 1));  
		simpleGraph.addNodeWithDefinition(NodeDefinition("C", nil, true));  
		simpleGraph.addDependencyFrom(NodeIdentifier("B", 1), to: NodeIdentifier("A"));  
		simpleGraph.addDependencyFrom(NodeIdentifier("C"), to: NodeIdentifier("B", 1)); ``
		
and then

`` dispatch_async(dispatch\_get\_global\_queue(DISPATCH\_QUEUE\_PRIORITY\_DEFAULT, 0)) {  
			simpleGraph.process() {
				nodeIdentifier in
				println("\(nodeIdentifier.identifier)")	// do something useful instead ...  
			}  
		} ``

Further work
------------

AsyncGraph is not complete. For example, it lacks cycle detection. This may not be a problem for small graphs that you can
keep under control, but it can deadlock if you aren't careful enough with the dependencies.
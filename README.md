SwiftAsyncGraph
===============

AsyncGraph is a simple graph asynchronous processor, written in Swift. AsyncGraph can help you to simplify synchronization between asynchronous but related tasks. Each task would be represented as a graph node, and then you would specify dependencies between tasks. AsyncGraph will process the task nodes, taking care of the dependencies for you. This way, you can focus on writing each task code and leave synchronization to the graph.

You can create a graph with an optional closure, and pass a closure to each node while defining the graph. When the graph is processed, it will execute the closure specified in the node. If no such closure exists, it will execute the default graph closure. This means that the node closures take precedence over the graph closure.

Each task node will be executed in its own thread. You also have the possibility of defining non-concurrent nodes that will be executed exclusively, for example for dealing with high memory demand tasks or scarce resources. This has been modelled as [the second readers-writers problem](https://en.wikipedia.org/wiki/Readers%E2%80%93writers_problem#The_second_readers-writers_problem), with writer priority, where non-concurrent nodes are writers.

How to use AsyncGraph
---------------------

To use AsyncGraph, simply copy the AsyncGraph.swift file to your project. There is a sample iOS project, AsyncGraphDemo, showing an example of how it works. You can also browse the tests for some basic use cases.

Sample usage:

[code lang="objc"]
let simpleGraph = AsyncGraph<Int, Void> {
	identifier, operation, graph in
	println("Now executing node \(identifier)")
}.addNodeWithIdentifier(1)
.addNodeWithIdentifier(2)
.addNodeWithIdentifier(3)
.addDependencyFrom(3, to: 2)

simpleGraph.processSynchronous()
[/code]

This code will create a graph where its identifiers are Ints, and the return type of each node processed will be Void. Then, it adds 3 nodes with identifiers 1, 2, and 3, and sets the dependencies between them. When the graph is defined, the processSynchronous function processes the graph, blocking the current thread until all nodes have been processed. The nodes identified by 1 and 2 will execute concurrently, but node with identifier 3 will wait until node with identifier 2 has finished processing. The closure executed in each node will be the default one specified in the graph constructor, which simply prints the node identifier. The closure receives 3 parameters: the node identifier, the NSOperation object that is currently being execute as each node is really an NSOperation executed in a NSOperationQueue, and the graph itself. As the result type is Void, no return statement is needed.

Features
--------

* Thanks to generics, you can create graphs using the type that suits your algorithm best as identifiers, provided they implement the Hashable and Equatable protocols. You can also specify the result type of each node processing, or you can use Void if you don't need to store a result value. Specifying result values is useful because this way you don't need to store the result yourself. The graph will store it for you, and you can retrieve it later, for example in a dependant node, with the method graph.resultFrom(identifier).
* Fluent interface that allows you to create the graph in one line, improving readability. For synchronous processing, you don't even need to create a variable, you can call the processSynchronous() method after the node and dependency definition, and it will process the anonymous graph.
* Synchronous and asynchronous processing. While synchronous processing is very easy to accomplish, but it may not be what you need. You can also call the process() method. This method will return immediately, and will return a reference to the graph. You can then pause, resume or cancel the execution.
* You can add a closure that will be executed when the graph is fully processed. This is useful for asynchronous graph processing.
* Node specific or default graph closure. If every node does a different kind of processing, you can set the closure when creating the node. In simple cases where all nodes do some processing based on the identifier, it is easier and more readable to specify a default closure when creating the graph.
* You can add closures to be executed before or after some node is processed. This is useful in cases where each node executes the same code, but in some cases you need to do some additional processing. This allows you to keep the node closure as simple as possible, and get the special cases out of your main code. This could be as simple as showing an alert, or as complicated as computing some statistical data based on your results.

//
//  AsyncGraphDemoTests.swift
//  AsyncGraphDemoTests
//
//  Created by Boolky Bear on 2/12/14.
//  Copyright (c) 2014 ByBDesigns. All rights reserved.
//

import UIKit
import XCTest

struct NodeIdentifier
{
	let identifier: String
	let tag: Int?
	
	init (_ identifier: String, _ tag: Int? = nil)
	{
		self.identifier = identifier
		self.tag = tag
	}
	
	func toString() -> String {
		let tagStr = self.tag.map { "\($0)" } ?? "null"
		
		return "\(self.identifier) - \(tagStr)"
	}
	
	var hashValue: Int {
		return self.toString().hashValue
	}
}

func == (lhs: NodeIdentifier, rhs: NodeIdentifier) -> Bool {
	return lhs.identifier == rhs.identifier && lhs.tag == rhs.tag
}

class AsyncGraphDemoTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
//    func testExample() {
//        // This is an example of a functional test case.
//        XCTAssert(true, "Pass")
//    }
//    
//    func testPerformanceExample() {
//        // This is an example of a performance test case.
//        self.measureBlock() {
//            // Put the code you want to measure the time of here.
//        }
//    }
	
	func testNodeIdentifiers()
	{
		let node1nil = NodeIdentifier("one")
		let node1tag = NodeIdentifier("one", 1)
		let node2nil = NodeIdentifier("two")
		let node2tag = NodeIdentifier("two", 1)
		let other1nil = NodeIdentifier("one")
		let other1tag1 = NodeIdentifier("one", 1)
		let other1tag2 = NodeIdentifier("one", 2)
		
		XCTAssertFalse(node1nil == node1tag, "Nodes with different tags should not be equal")
		XCTAssertFalse(node1nil == node2nil, "Nodes with different identifiers should not be equal")
		XCTAssertFalse(node1tag == node2tag, "Nodes with different identifiers should not be equal, even tag is equal")
		XCTAssert(node1nil == other1nil, "Nodes with same identifier and same tag should be equal")
		XCTAssert(node1tag == other1tag1, "Nodes with same identifier and same tag should be equal")
		XCTAssertFalse(node1tag == other1tag2, "Nodes with different tags should not be equal, even identifier is equal")
	}

	func testTwoIndependentItems()
	{
		let times: [ String : NSTimeInterval ] = [ "first" : 0.5,
			"second" : 1.0, ]
		var finishOrder = [String]()
		
		AsyncGraph<String, Void> {
			nodeIdentifier, operation, graph in
			
			NSThread.sleepForTimeInterval(NSTimeInterval(times[nodeIdentifier]!))
			
			finishOrder.append(nodeIdentifier)
			
			return nil
		}
			.addNodeWithIdentifier("first")
			.addNodeWithIdentifier("second")
			.processSynchronous()
		
		XCTAssertEqual(finishOrder, [ "first", "second" ], "Finish order should be first, second")
	}
	
	func testTwoDependentItems()
	{
		let times: [ String : NSTimeInterval ] = [ "first" : 0.5,
			"second" : 1.0, ]
		var finishOrder = [String]()
		
		AsyncGraph<String, Void> {
			nodeIdentifier, operation, graph in
			
			NSThread.sleepForTimeInterval(NSTimeInterval(times[nodeIdentifier]!))
			
			finishOrder.append(nodeIdentifier)
			
			return nil
		}
			.addNodeWithIdentifier("first")
			.addNodeWithIdentifier("second")
			.addDependencyFrom("second", to: "first")
			.processSynchronous()
		
		XCTAssertEqual(finishOrder, [ "first", "second" ], "Finish order should be first, second")
	}
	
	func testTwoDependentItemsReversed()
	{
		let times: [ String : NSTimeInterval ] = [ "first" : 0.5,
			"second" : 1.0, ]
		var finishOrder = [String]()
		
		AsyncGraph<String, Void> {
			nodeIdentifier, operation, graph in
			
			NSThread.sleepForTimeInterval(NSTimeInterval(times[nodeIdentifier]!))
			
			finishOrder.append(nodeIdentifier)
			
			return nil
		}
			.addNodeWithIdentifier("first")
			.addNodeWithIdentifier("second")
			.addDependencyFrom("first", to: "second")
			.processSynchronous()
		
		XCTAssertEqual(finishOrder, [ "second", "first" ], "Finish order should be second, first")
	}
	
	func testAsyncOperationGraph()
	{
		let graph = AsyncGraph<String, String>()
		
		var result = [ String ]()
		graph.addNodeWithIdentifier("5") {
			identifier, operation, graph in
			
			NSThread.sleepForTimeInterval(5.0)
			
			result.append(identifier)
			
			return nil
			}.addNodeWithIdentifier("3") {
				identifier, operation, graph in
				
				NSThread.sleepForTimeInterval(3.0)
				
				result.append(identifier)
				
				return nil
			}.processSynchronous()
		
		let resultString = join("#", result)
		XCTAssert(resultString == "3#5")
	}
	
	func testAsyncOperationGraphWithDependencies()
	{
		let graphWithDependencies = AsyncGraph<String, String>()
		
		var resultWithDependencies = [ String ]()
		graphWithDependencies.addNodeWithIdentifier("5") {
			identifier, operation, graph in
			
			NSThread.sleepForTimeInterval(5.0)
			
			resultWithDependencies.append(identifier)
			
			return nil
			}.addNodeWithIdentifier("3") {
				identifier, operation, graph in
				
				NSThread.sleepForTimeInterval(3.0)
				
				resultWithDependencies.append(identifier)
				
				return nil
			}.addDependencyFrom("3", to: "5")
			.processSynchronous()
		
		let resultWithDependenciesString = join("#", resultWithDependencies)
		XCTAssert(resultWithDependenciesString == "5#3")
	}
	
	func testAsyncOperationGraphDefault()
	{
		var resultDefault = [ String ]()
		
		let graphWithDefault = AsyncGraph<String, String> {
			identifier, operation, graph in
			
			let timeInterval = NSTimeInterval(identifier.toInt() ?? 0)
			
			NSThread.sleepForTimeInterval(timeInterval)
			
			resultDefault.append(identifier)
			
			return nil
		}
		
		graphWithDefault.addNodeWithIdentifier("5")
			.addNodeWithIdentifier("3")
			.processSynchronous()
		
		let resultDefaultString = join("#", resultDefault)
		XCTAssert(resultDefaultString == "3#5")
	}
	
	func testAsyncOperationHooks()
	{
		let graph = AsyncGraph<Int, String> {
			identifier, operation, graph in
			
			NSThread.sleepForTimeInterval(NSTimeInterval(identifier))
			
			return "\(identifier)"
		}
		
		var isCompleted = false
		var before = 0
		var after = 0
		
		let expectation = expectationWithDescription("Test graph")
		
		graph.addNodeWithIdentifier(3)
			.addNodeWithIdentifier(5)
			.addHook {
				graph in
				
				expectation.fulfill()
				
				isCompleted = true
			}
			.addHookBeforeNode(3) {
				identifier, operation, graph in
				
				before += identifier
			}
			.addHookAfterNode(5) {
				identifier, operation, graph in
				
				after -= identifier
			}
			.process()
		
		waitForExpectationsWithTimeout(10) { (error) in
			XCTAssertNil(error, "\(error)")
		}
		
		XCTAssert(isCompleted, "Graph has not been completed")
		XCTAssert(graph.resultFromNode(3) == "3")
		XCTAssert(graph.resultFromNode(5) == "5")
		XCTAssert(graph.status == .Processed)
		XCTAssert(before == 3)
		XCTAssert(after == -5)
	}
	
	func testCancel()
	{
		let graph = AsyncGraph<Int, String> {
			identifier, operation, graph in
			
			NSThread.sleepForTimeInterval(NSTimeInterval(identifier))
			
			return "\(identifier)"
		}
		
		let expectation = expectationWithDescription("Test graph")
		
		graph.addNodeWithIdentifier(3)
			.addHook {
				graph in
				
				expectation.fulfill()
			}
			.process()
		
		graph.cancel()
		
		waitForExpectationsWithTimeout(10) { (error) in
			XCTAssertNil(error, "\(error)")
		}
		
		XCTAssert(graph.status == .Cancelled)
	}
}

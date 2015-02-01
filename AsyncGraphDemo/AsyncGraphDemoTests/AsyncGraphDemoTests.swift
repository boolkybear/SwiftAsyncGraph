//
//  AsyncGraphDemoTests.swift
//  AsyncGraphDemoTests
//
//  Created by Boolky Bear on 2/12/14.
//  Copyright (c) 2014 ByBDesigns. All rights reserved.
//

import UIKit
import XCTest

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
		
		XCTAssertNotEqual(node1nil, node1tag, "Nodes with different tags should not be equal")
		XCTAssertNotEqual(node1nil, node2nil, "Nodes with different identifiers should not be equal")
		XCTAssertNotEqual(node1tag, node2tag, "Nodes with different identifiers should not be equal, even tag is equal")
		XCTAssertEqual(node1nil, other1nil, "Nodes with same identifier and same tag should be equal")
		XCTAssertEqual(node1tag, other1tag1, "Nodes with same identifier and same tag should be equal")
		XCTAssertNotEqual(node1tag, other1tag2, "Nodes with different tags should not be equal, even identifier is equal")
	}

	func testTwoIndependentItems()
	{
		let graph = AsyncGraph(builder: GraphDefinitionBuilder().addNode("first").addNode("second"))
		
		let times: [ String : NSTimeInterval ] = [ "first" : 0.5,
			"second" : 1.0, ]
		var finishOrder = [String]()
		
		graph.process {
			nodeIdentifier in
			
			NSThread.sleepForTimeInterval(NSTimeInterval(times[nodeIdentifier.identifier]!))
			
			finishOrder.append(nodeIdentifier.identifier)
			
			return nil
		}
		
		XCTAssertEqual(finishOrder, [ "first", "second" ], "Finish order should be first, second")
	}
	
	func testTwoDependentItems()
	{
		let graph = AsyncGraph(builder: GraphDefinitionBuilder()
			.addNode("first").addNode("second")
			.addDependency("second", toIdentifier: "first"))
		
		let times: [ String : NSTimeInterval ] = [ "first" : 0.5,
			"second" : 1.0, ]
		var finishOrder = [String]()
		
		graph.process {
			nodeIdentifier in
			
			NSThread.sleepForTimeInterval(NSTimeInterval(times[nodeIdentifier.identifier]!))
			
			finishOrder.append(nodeIdentifier.identifier)
			
			return nil
		}
		
		XCTAssertEqual(finishOrder, [ "first", "second" ], "Finish order should be first, second")
	}
	
	func testTwoDependentItemsReversed()
	{
		let graph = AsyncGraph(builder: GraphDefinitionBuilder()
			.addNode("first").addNode("second")
			.addDependency("first", toIdentifier: "second"))
		
		let times: [ String : NSTimeInterval ] = [ "first" : 0.5,
			"second" : 1.0, ]
		var finishOrder = [String]()
		
		graph.process {
			nodeIdentifier in
			
			NSThread.sleepForTimeInterval(NSTimeInterval(times[nodeIdentifier.identifier]!))
			
			finishOrder.append(nodeIdentifier.identifier)
			
			return nil
		}
		
		XCTAssertEqual(finishOrder, [ "second", "first" ], "Finish order should be second, first")
	}
}

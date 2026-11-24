//
//  ArrayValueTransformer.swift
//  WorkoutApp
//
//  Created by Justus Besser on 25.03.25.
//

import Foundation

@objc(StringArrayValueTransformer)
public class StringArrayValueTransformer: ValueTransformer {
    
    public override class func transformedValueClass() -> AnyClass {
        return NSData.self
    }
    
    public override class func allowsReverseTransformation() -> Bool {
        return true
    }
    
    public override func transformedValue(_ value: Any?) -> Any? {
        guard let stringArray = value as? [String] else {
            // Return empty data for empty arrays instead of nil
            return try? JSONEncoder().encode([String]()) as NSData
        }
        
        do {
            let jsonData = try JSONEncoder().encode(stringArray)
            return jsonData as NSData
        } catch {
            appLog("Error encoding string array: \(error)")
            return try? JSONEncoder().encode([String]()) as NSData
        }
    }
    
    public override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else {
            return [String]() // Return empty array instead of nil
        }
        
        do {
            let stringArray = try JSONDecoder().decode([String].self, from: data)
            return stringArray
        } catch {
            appLog("Error decoding string array: \(error)")
            return [String]() // Return empty array on error
        }
    }
    
    public static func register() {
        let transformer = StringArrayValueTransformer()
        ValueTransformer.setValueTransformer(
            transformer,
            forName: NSValueTransformerName("StringArrayValueTransformer")
        )
    }
}

@objc(IntArrayValueTransformer)
public class IntArrayValueTransformer: ValueTransformer {
    
    public override class func transformedValueClass() -> AnyClass {
        return NSData.self
    }
    
    public override class func allowsReverseTransformation() -> Bool {
        return true
    }
    
    public override func transformedValue(_ value: Any?) -> Any? {
        guard let intArray = value as? [Int] else { return nil }
        
        do {
            let jsonData = try JSONEncoder().encode(intArray)
            return jsonData as NSData
        } catch {
            appLog("Error encoding int array: \(error)")
            return nil
        }
    }
    
    public override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        
        do {
            let intArray = try JSONDecoder().decode([Int].self, from: data)
            return intArray
        } catch {
            appLog("Error decoding int array: \(error)")
            return nil
        }
    }
    
    public static func register() {
        let transformer = IntArrayValueTransformer()
        ValueTransformer.setValueTransformer(
            transformer,
            forName: NSValueTransformerName("IntArrayValueTransformer")
        )
    }
}

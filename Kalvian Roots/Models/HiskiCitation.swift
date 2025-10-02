//
//  HiskiCitation.swift
//  Kalvian Roots
//
//  Citation structure for HisKi database records
//
//  Created by Michael Bendio on 10/1/25.
//

import Foundation

/**
 * HiskiCitation - Represents a citation to a HisKi database record
 *
 * Contains the URL and metadata for a specific church record from hiski.genealogia.fi
 */
struct HiskiCitation {
    let recordType: EventType
    let personName: String
    let date: String
    let url: String
    let recordId: String
    let spouse: String?
}

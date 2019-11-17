//
//  File.swift
//  
//
//  Created by David Nadoba on 17.11.19.
//

import Foundation
import Network

extension FixedWidthInteger {
    var networkByteOrder: Self { bigEndian }
}

extension UnsignedInteger {
    /// A collection containing the words of this value’s binary representation, in order from the least significant to most significant.
    var data: Data {
        var copy = self
        return Data(bytes: &copy, count: MemoryLayout<Self>.size)
    }
}

extension IPv4Address {
    static func sACN(universe: UInt16) -> IPv4Address? {
        IPv4Address(Data([239, 255] + universe.networkByteOrder.data))
    }
    static var sACNUniverDiscovery: IPv4Address { .sACN(universe: 64214)! }
}

let rootLayerTemplate = Data([
    // ---- Root Layer ------
    // Preamble Size
    0x00, 0x10,
    // Post-amble Size
    0x00, 0x00,
    // ACN Package Identifier - Identifies this packet as E1.17
    0x41, 0x53, 0x43, 0x2d, 0x45, 0x31, 0x2e, 0x31, 0x37, 0x00, 0x00, 0x00,
    // Flags and Length - not yet set
    0x00, 0x07,
    // Vector - Identifies RLP Data as 1.31 Protocol PDU
    0x00, 0x00, 0x00, 0x04,
    // Sender's CID (Component Identifier) - not yet set
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
])
fileprivate let uuidSize = 16

func flagsAndLength(length: UInt16, flags: UInt8 = 0x07) -> UInt16 {
    // Low 12 bits = PDU length
    let escapedLength = length              & 0b0000_1111_1111_1111
    // High 4 bits = 0x7
    let escapedFlags  = UInt16(flags) << 12 & 0b1111_0000_0000_0000
    return escapedFlags | escapedLength
}

fileprivate struct RootLayer {
    private static let lengthStartingByte: UInt16 = 16
    private static let cidRange = 22...37
    private static let flagsAndLengthRange = 16...17
    
    private let cidData: Data
    init(cid: UUID) {
        let data = cid.uuid
        self.cidData = Data([
            data.0, data.1, data.2,  data.3,  data.4,  data.5,  data.6,  data.7,
            data.8, data.9, data.10, data.11, data.12, data.13, data.14, data.15,
        ])
    }
    var count: Int { rootLayerTemplate.count }
    func write(to data: inout Data, fullPackageLength: UInt16) {
        data[0..<rootLayerTemplate.count] = rootLayerTemplate
        data[RootLayer.cidRange] = cidData
        let pduLength = fullPackageLength - (Self.lengthStartingByte - 1)
        data[RootLayer.flagsAndLengthRange] = flagsAndLength(length: pduLength).networkByteOrder.data
    }
}

let dmxDataFramingLayerTemplate = Data([
    // ---- E1.31 Framing Layer ------
    // Flags and Length - not yet set
    0x00, 0x07,
    // Vector - Identifies 1.31 data as DMP Protocol PDU
    0x00, 0x00, 0x00, 0x02,
    // Source Name - Userassigned Name of Source - not yet set
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    // Priority - Data priority if multiple sources
    100,
    // Synchronization Address - Universe address on which sync packets will be sent - not yet set
    0x00, 0x00,
    // Sequence Number - To detect duplicate or out of order packets - not yet set
    0x00,
    // Options Flags
    // Bit 7 = Preview_Data
    // Bit 6 = Stream_Terminated
    // Bit 5 = Force_Synchronization
    0x00,
    // Universe Number - Identifier for a distinct stream of DMX512-A [DMX] Data - not yet set
    0x00, 0x00,
])

public struct DMXDataFramingOptions: OptionSet, RawRepresentable {
    public static let previewData = DMXDataFramingOptions(rawValue: 0b0100_0000)
    public static let streamTerminatd = DMXDataFramingOptions(rawValue: 0b0010_0000)
    public static let forceSynchronization = DMXDataFramingOptions(rawValue: 0b0001_0000)
    public static let none: DMXDataFramingOptions = []
    public var rawValue: UInt8
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
}


fileprivate struct DMXDataFramingLayer {
    private static let lengthStartingByte: UInt16 = 48
    static let flagsAndLengthRange = 38...39
    static let sourceNameRange = 44...107
    static let priorityRange = 108..<109
    static let synchronizationUniverseRange = 109...110
    static let sequenceNumberRange = 111...111
    static let optionsRange = 112...112
    static let universeRange = 113...114
    
    
    var sourceNameData: Data
    var universe: UInt16
    var priority: UInt8 = 101
    var synchronizationUniverse: UInt16 = 0
    var options: DMXDataFramingOptions = .none
    var count: Int { dmxDataFramingLayerTemplate.count }
    
    init(
       sourceName: String,
       universe: UInt16,
       priority: UInt8 = 101,
       synchronizationUniverse: UInt16 = 0,
       options: DMXDataFramingOptions = .none
    ) {
        self.universe = universe
        self.priority = priority
        self.synchronizationUniverse = synchronizationUniverse
        self.options = options
        sourceNameData = String(
            sourceName.utf8.prefix(DMXDataFramingLayer.sourceNameRange.count - 1)
        )?.data(using: .utf8) ?? Data()
    }
    
    func write(to data: inout Data, fullPackageLength: UInt16, sequenceNumber: UInt8) {
        data[38...114] = dmxDataFramingLayerTemplate
        let pduLength = fullPackageLength - (Self.lengthStartingByte - 1)
        data[DMXDataFramingLayer.flagsAndLengthRange] = flagsAndLength(length: pduLength).networkByteOrder.data
        
        
        let sourceNameRange = DMXDataFramingLayer.sourceNameRange.lowerBound..<(DMXDataFramingLayer.sourceNameRange.lowerBound + sourceNameData.count)
        data[sourceNameRange] = sourceNameData
        
        data[DMXDataFramingLayer.priorityRange] = priority.networkByteOrder.data
        data[DMXDataFramingLayer.synchronizationUniverseRange] = synchronizationUniverse.networkByteOrder.data
        data[DMXDataFramingLayer.sequenceNumberRange] = sequenceNumber.networkByteOrder.data
        data[DMXDataFramingLayer.optionsRange] = options.rawValue.networkByteOrder.data
        data[DMXDataFramingLayer.universeRange] = universe.networkByteOrder.data
    }
}

let dmpLayerTemplate = Data([
    // ----- Device Management Protocol Layer -----
    // Flags and Length - not yet set
    0x00, 0x07,
    // Vector - Identifies DMP Set Property Message PDU
    0x02,
    // Address Type & Data Type - Identifies format of address and data
    0xa1,
    // First Property Address - Indicates DMX512-A START Code is at DMP address 0
    // Receivers shall discard the packet if the received value is not 0x0000.
    0x00, 0x00,
    // Address Increment - Indicates each property is 1 octet
    0x00, 0x01,
    // Property value count - 0x0001 -- 0x0201
    0x00, 0x01,
    // Property values - DMX512-A START Code + data
    0x00,
])
/// Device Management Protocol Layer
struct DMPLayer {
    private static let lengthStartingByte: UInt16 = 115
    static let propertyValueCountRange = 123...124
    static let flagsAndLengthRange = 115...116
    
    var dmxData: Data
    var count: Int {
        dmpLayerTemplate.count + dmxData.count
    }
    func write(
        to data: inout Data,
        fullPackageLength: UInt16
    ) {
        assert(dmxData.count <= 512)
        data[115...125] = dmpLayerTemplate
        let pduLength = fullPackageLength - (Self.lengthStartingByte - 1)
        data[DMPLayer.flagsAndLengthRange] = flagsAndLength(length: pduLength).networkByteOrder.data
        data[DMPLayer.propertyValueCountRange] = UInt16(1 + dmxData.count).networkByteOrder.data
        data[126..<(126 + dmxData.count)] = dmxData
    }
}

fileprivate struct DataPacket {
    var rootLayer: RootLayer
    var framingLayer: DMXDataFramingLayer
    var dmpLayer: DMPLayer
    
    var count: Int {
        rootLayer.count + framingLayer.count + dmpLayer.count
    }
    func getData(sequenceNumber: UInt8) -> Data {
        let count = self.count
        var data = Data(count: count)
        rootLayer.write(to: &data, fullPackageLength: UInt16(count))
        framingLayer.write(to: &data, fullPackageLength: UInt16(count), sequenceNumber: sequenceNumber)
        dmpLayer.write(to: &data, fullPackageLength: UInt16(count))
        return data
    }
}
#if os(iOS) || os(tvOS)
import UIKit
#endif
public func getDeviceName() -> String {
    #if os(iOS) || os(tvOS)
    return UIDevice.current.name
    #elseif os(macOS)
    return Host.current().localizedName!
    #endif
}

public class Client {
    public let queue = DispatchQueue(label: "sACN.udp.send.queue")
    let connection: NWConnection
    private let rootLayer: RootLayer
    private let dataFramginLayer: DMXDataFramingLayer
    private(set) var sequenceNumber: UInt8 = 0
    public init(cid: UUID = .init(), sourceName: String = getDeviceName(), universe: UInt16) {
        rootLayer = RootLayer(cid: cid)
        dataFramginLayer = .init(sourceName: sourceName, universe: universe)
        let p = NWParameters.udp
        
        p.serviceClass = .responsiveData
        let connection = NWConnection(
            host: .ipv4(.sACN(universe: 1)!),
            port: 5568,
            using: p
        )
        self.connection = connection

        connection.start(queue: queue)
    }
    private func getNextSequenceNumber() -> UInt8 {
        sequenceNumber &+= 1
        return sequenceNumber
    }
    public func sendDMXData(_ data: Data) {
        let dmpLayer = DMPLayer(dmxData: data)
        let packet = DataPacket(rootLayer: rootLayer, framingLayer: dataFramginLayer, dmpLayer: dmpLayer)
        let packetData = packet.getData(sequenceNumber: getNextSequenceNumber())
        connection.send(content: packetData, completion: .idempotent)
    }
}

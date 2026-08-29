import WinSDK
import WinSDK.DirectX

/// Borrows the renderer's device/context. The renderer detaches the collector
/// before releasing either, which releases every query in this transport.
/// This transport stays on the same execution owner as that renderer.
final class D3D11TimestampQueryTransport: GPUTimestampQueryTransport {
    private let device: UnsafeMutablePointer<ID3D11Device>
    private let context: UnsafeMutablePointer<ID3D11DeviceContext>
    private var queries: [Int: UnsafeMutablePointer<ID3D11Query>] = [:]
    private var nextHandle = 0

    init(device: UnsafeMutablePointer<ID3D11Device>, context: UnsafeMutablePointer<ID3D11DeviceContext>) {
        self.device = device
        self.context = context
    }

    var ownedQueryCount: Int { queries.count }

    func createQuery(_ kind: GPUTimestampQueryKind) -> (hresult: Int32, handle: Int?) {
        var descriptor = D3D11_QUERY_DESC()
        descriptor.Query = kind == .timestamp ? D3D11_QUERY_TIMESTAMP : D3D11_QUERY_TIMESTAMP_DISJOINT
        descriptor.MiscFlags = 0
        var query: UnsafeMutablePointer<ID3D11Query>?
        let hresult = makeCOM(into: &query) { output in
            device.pointee.lpVtbl.pointee.CreateQuery(device, &descriptor, &output)
        }
        guard hresult == 0, let ownedQuery = query else {
            releaseCOM(&query)
            return (hresult, nil)
        }
        let handle = nextHandle
        nextHandle &+= 1
        queries[handle] = ownedQuery
        return (hresult, handle)
    }

    func releaseQuery(_ handle: Int) {
        var query = queries.removeValue(forKey: handle)
        releaseCOM(&query)
    }

    func beginQuery(_ handle: Int) {
        guard let query = asynchronousQuery(handle) else { return }
        context.pointee.lpVtbl.pointee.Begin(context, query)
    }

    func endQuery(_ handle: Int) {
        guard let query = asynchronousQuery(handle) else { return }
        context.pointee.lpVtbl.pointee.End(context, query)
    }

    func readTimestamp(_ handle: Int) -> (hresult: Int32, value: UInt64) {
        guard let query = asynchronousQuery(handle) else { return (Int32(bitPattern: 0x8000_4003), 0) }
        var value: UInt64 = 0
        let hresult = context.pointee.lpVtbl.pointee.GetData(
            context, query, &value, UINT(MemoryLayout<UInt64>.size),
            UINT(D3D11_ASYNC_GETDATA_DONOTFLUSH.rawValue))
        return (hresult, value)
    }

    func readDisjoint(_ handle: Int) -> (hresult: Int32, frequency: UInt64, isDisjoint: Bool) {
        guard let query = asynchronousQuery(handle) else { return (Int32(bitPattern: 0x8000_4003), 0, false) }
        var value = D3D11_QUERY_DATA_TIMESTAMP_DISJOINT()
        let hresult = context.pointee.lpVtbl.pointee.GetData(
            context, query, &value, UINT(MemoryLayout<D3D11_QUERY_DATA_TIMESTAMP_DISJOINT>.size),
            UINT(D3D11_ASYNC_GETDATA_DONOTFLUSH.rawValue))
        return (hresult, value.Frequency, value.Disjoint.boolValue)
    }

    private func asynchronousQuery(_ handle: Int) -> UnsafeMutablePointer<ID3D11Asynchronous>? {
        queries[handle].map { UnsafeMutableRawPointer($0).assumingMemoryBound(to: ID3D11Asynchronous.self) }
    }
}

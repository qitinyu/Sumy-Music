/**
 * TagReader - 手动内嵌标签解析器（不依赖系统 AVMetadataExtractor）
 * 支持：
 *  - MP3 ID3v2.2 / v2.3 / v2.4：TIT2/TT2(歌名) TPE1/TP1(歌手) TALB/TAL(专辑)
 *    USLT/ULT(歌词) APIC/PIC(封面)
 *  - FLAC：Vorbis Comment（TITLE/ARTIST/ALBUM/LYRICS/METADATA_BLOCK_PICTURE）
 *    + PICTURE 元数据块
 * 修复 MusicTag 等工具写入的内嵌封面/歌手/歌名/歌词无法读取的问题。
 */
import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { CompatUtils } from './CompatUtils'

export interface EmbeddedTags {
  title: string
  artist: string
  album: string
  lyric: string
  coverBytes: Uint8Array | null
  coverMime: string
}

interface EmbeddedPicture {
  bytes: Uint8Array
  mime: string
}

export class TagReader {

  static readTags(filePath: string): EmbeddedTags | null {
    let fd: number = -1
    try {
      let openUri: string = filePath
      if (openUri.startsWith('file://')) {
        openUri = openUri.slice(7)
      }
      const file = fileIo.openSync(openUri, fileIo.OpenMode.READ_ONLY)
      fd = file.fd
      const header = new ArrayBuffer(4)
      fileIo.readSync(fd, header)
      const h = new Uint8Array(header)
      if (h[0] === 0x49 && h[1] === 0x44 && h[2] === 0x33) {
        return TagReader.readId3v2(fd)
      }
      if (h[0] === 0x66 && h[1] === 0x4C && h[2] === 0x61 && h[3] === 0x43) {
        return TagReader.readFlac(fd)
      }
      return null
    } catch (_e) {
      return null
    } finally {
      if (fd >= 0) {
        try {
          fileIo.closeSync(fd)
        } catch (_e) {
        }
      }
    }
  }

  /** 从内存字节解析内嵌标签（云端歌曲仅下载文件头后调用） */
  static readTagsFromBytes(bytes: Uint8Array): EmbeddedTags | null {
    if (!bytes || bytes.length < 8) {
      return null
    }
    if (bytes[0] === 0x49 && bytes[1] === 0x44 && bytes[2] === 0x33) {
      return TagReader.parseId3v2Bytes(bytes)
    }
    if (bytes[0] === 0x66 && bytes[1] === 0x4C && bytes[2] === 0x61 && bytes[3] === 0x43) {
      return TagReader.parseFlacBytes(bytes)
    }
    return null
  }

  private static emptyTags(): EmbeddedTags {
    return {
      title: '',
      artist: '',
      album: '',
      lyric: '',
      coverBytes: null,
      coverMime: '',
    }
  }

  private static hasContent(tags: EmbeddedTags): boolean {
    return tags.title.length > 0 || tags.artist.length > 0 || tags.album.length > 0 ||
      tags.lyric.length > 0 || (tags.coverBytes !== null && tags.coverBytes.length > 0)
  }

  // ==================== ID3v2 ====================

  private static readId3v2(fd: number): EmbeddedTags | null {
    const restHeader = new ArrayBuffer(6)
    fileIo.readSync(fd, restHeader)
    const h = new Uint8Array(restHeader)
    const version: number = h[0]
    const flags: number = h[1]
    const tagSize: number = ((h[2] & 0x7F) << 21) | ((h[3] & 0x7F) << 14) | ((h[4] & 0x7F) << 7) | (h[5] & 0x7F)
    if (tagSize <= 0 || tagSize > 20 * 1024 * 1024) {
      return null
    }
    const tagData = new ArrayBuffer(tagSize)
    fileIo.readSync(fd, tagData)
    const tags: EmbeddedTags = TagReader.parseId3v2TagData(new Uint8Array(tagData), version, flags)
    return TagReader.hasContent(tags) ? tags : null
  }

  private static parseId3v2Bytes(bytes: Uint8Array): EmbeddedTags | null {
    if (bytes.length < 10) {
      return null
    }
    const version: number = bytes[3]
    const flags: number = bytes[5]
    const tagSize: number = ((bytes[6] & 0x7F) << 21) | ((bytes[7] & 0x7F) << 14) | ((bytes[8] & 0x7F) << 7) | (bytes[9] & 0x7F)
    if (tagSize <= 0 || tagSize > 20 * 1024 * 1024) {
      return null
    }
    const avail: number = bytes.length - 10
    const len: number = Math.min(tagSize, avail)
    const tags: EmbeddedTags = TagReader.parseId3v2TagData(bytes.subarray(10, 10 + len), version, flags)
    return TagReader.hasContent(tags) ? tags : null
  }

  // 遍历 ID3v2 帧（v2.2 帧头 6 字节，v2.3/v2.4 帧头 10 字节）
  private static parseId3v2TagData(data: Uint8Array, version: number, flags: number): EmbeddedTags {
    const tags: EmbeddedTags = TagReader.emptyTags()
    const tagSize: number = data.length
    let offset: number = 0
    // 扩展头（v2.3/v2.4）
    if (version >= 3 && (flags & 0x40) !== 0) {
      if (offset + 4 <= tagSize) {
        const extSize: number = (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3]
        offset = version >= 4 ? extSize : extSize + 4
      }
    }

    const isV2: boolean = version === 2
    const headerLen: number = isV2 ? 6 : 10
    while (offset + headerLen <= tagSize) {
      if (data[offset] === 0x00) {
        break
      }
      let frameId: string = ''
      let frameSize: number = 0
      if (isV2) {
        frameId = String.fromCharCode(data[offset], data[offset + 1], data[offset + 2])
        frameSize = (data[offset + 3] << 16) | (data[offset + 4] << 8) | data[offset + 5]
      } else {
        frameId = String.fromCharCode(data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
        if (version >= 4) {
          frameSize = ((data[offset + 4] & 0x7F) << 21) | ((data[offset + 5] & 0x7F) << 14) |
            ((data[offset + 6] & 0x7F) << 7) | (data[offset + 7] & 0x7F)
        } else {
          frameSize = (data[offset + 4] << 24) | (data[offset + 5] << 16) | (data[offset + 6] << 8) | data[offset + 7]
        }
      }
      offset += headerLen
      if (frameSize <= 0 || offset + frameSize > tagSize) {
        break
      }
      const frameData: Uint8Array = data.subarray(offset, offset + frameSize)
      TagReader.handleId3Frame(tags, frameId, frameData)
      offset += frameSize
    }
    return tags
  }

  private static handleId3Frame(tags: EmbeddedTags, frameId: string, frameData: Uint8Array): void {
    const id: string = frameId.toUpperCase()
    if (id === 'TIT2' || id === 'TT2') {
      if (tags.title.length === 0 && frameData.length > 1) {
        tags.title = TagReader.decodeTextFrame(frameData)
      }
    } else if (id === 'TPE1' || id === 'TP1') {
      if (tags.artist.length === 0 && frameData.length > 1) {
        tags.artist = TagReader.decodeTextFrame(frameData)
      }
    } else if (id === 'TALB' || id === 'TAL') {
      if (tags.album.length === 0 && frameData.length > 1) {
        tags.album = TagReader.decodeTextFrame(frameData)
      }
    } else if (id === 'USLT' || id === 'ULT') {
      if (tags.lyric.length === 0 && frameData.length > 4) {
        const enc: number = frameData[0]
        // 编码(1) + 语言(3) + 内容描述符(按编码跳过 null 终止符)。
        // UTF-16(1/2) 的终止符是 2 字节 00 00，按单字节扫描会在第一个 0x00 处停半对，
        // 导致歌词从 UTF-16 字符的中间字节开始解码 → 整段乱码。
        const textStart: number = TagReader.skipId3String(frameData, 4, enc)
        if (textStart < frameData.length) {
          tags.lyric = TagReader.decodeTextBytes(frameData.subarray(textStart), enc)
        }
      }
    } else if (id === 'APIC') {
      if (tags.coverBytes === null && frameData.length > 8) {
        const pic = TagReader.parseApic(frameData)
        if (pic) {
          tags.coverBytes = pic.bytes
          tags.coverMime = pic.mime
        }
      }
    } else if (id === 'PIC') {
      // ID3v2.2：编码(1) + 图片格式(3) + 类型(1) + 描述 + 数据
      if (tags.coverBytes === null && frameData.length > 6) {
        const fmt: string = String.fromCharCode(frameData[1], frameData[2], frameData[3]).toUpperCase()
        let p: number = 4
        const descEnc: number = frameData[0]
        const afterDesc: number = TagReader.skipId3String(frameData, p, descEnc)
        p = afterDesc
        if (p < frameData.length) {
          tags.coverBytes = frameData.subarray(p)
          tags.coverMime = fmt === 'PNG' ? 'image/png' : (fmt === 'WEBP' ? 'image/webp' : 'image/jpeg')
        }
      }
    }
  }

  private static parseApic(frameData: Uint8Array): EmbeddedPicture | null {
    try {
      const enc: number = frameData[0]
      let p: number = 1
      let mimeEnd: number = p
      while (mimeEnd < frameData.length && frameData[mimeEnd] !== 0) {
        mimeEnd++
      }
      const mime: string = TagReader.bytesToString(frameData.subarray(p, mimeEnd)).toLowerCase()
      p = mimeEnd + 1
      p++ // 图片类型
      p = TagReader.skipId3String(frameData, p, enc)
      if (p >= frameData.length) {
        return null
      }
      return { bytes: frameData.subarray(p), mime: mime }
    } catch (_e) {
      return null
    }
  }

  // 跳过 ID3 文本串（描述符）：按编码处理 null 终止符
  private static skipId3String(data: Uint8Array, start: number, encoding: number): number {
    let p: number = start
    if (encoding === 1 || encoding === 2) {
      // UTF-16：先跳 BOM，再找 00 00
      if (p + 1 < data.length && data[p] === 0xFF && data[p + 1] === 0xFE) {
        p += 2
      } else if (p + 1 < data.length && data[p] === 0xFE && data[p + 1] === 0xFF) {
        p += 2
      }
      while (p + 1 < data.length && !(data[p] === 0 && data[p + 1] === 0)) {
        p += 2
      }
      return p + 2
    }
    while (p < data.length && data[p] !== 0) {
      p++
    }
    return p + 1
  }

  // ==================== FLAC ====================

  /** 从内存字节遍历 FLAC 元数据块（仅头部下载场景，遇到不完整块即停止） */
  private static parseFlacBytes(bytes: Uint8Array): EmbeddedTags | null {
    const tags: EmbeddedTags = TagReader.emptyTags()
    if (bytes.length < 8) {
      return null
    }
    let offset: number = 4 // 跳过 "fLaC"
    let isLast: boolean = false
    while (offset + 4 <= bytes.length) {
      const bh: number = bytes[offset]
      isLast = (bh & 0x80) !== 0
      const blockType: number = bh & 0x7F
      const blockSize: number = (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3]
      offset += 4
      if (blockSize <= 0 || blockSize > 10 * 1024 * 1024) {
        break
      }
      if (offset + blockSize > bytes.length) {
        break // 头部下载不够完整块
      }
      const block: Uint8Array = bytes.subarray(offset, offset + blockSize)
      if (blockType === 4) {
        TagReader.parseVorbisCommentBytes(block, tags)
      } else if (blockType === 6) {
        if (tags.coverBytes === null) {
          const p = TagReader.parseFlacPicture(block)
          if (p) {
            tags.coverBytes = p.bytes
            tags.coverMime = p.mime
          }
        }
      }
      offset += blockSize
      if (isLast) {
        break
      }
    }
    return TagReader.hasContent(tags) ? tags : null
  }

  private static parseVorbisCommentBytes(cd: Uint8Array, tags: EmbeddedTags): void {
    const blockSize: number = cd.length
    let offset: number = 0
    const vendorLen: number = TagReader.readUint32LE(cd, 0)
    offset = 4 + vendorLen
    if (offset + 4 > blockSize) {
      return
    }
    const commentCount: number = TagReader.readUint32LE(cd, offset)
    offset += 4
    for (let i = 0; i < commentCount && offset + 4 <= blockSize; i++) {
      const len: number = TagReader.readUint32LE(cd, offset)
      offset += 4
      if (offset + len > blockSize) {
        break
      }
      const commentBytes: Uint8Array = cd.subarray(offset, offset + len)
      offset += len
      const comment: string = TagReader.tryUtf8(commentBytes)
      const eqIdx: number = comment.indexOf('=')
      if (eqIdx > 0) {
        const key: string = comment.substring(0, eqIdx).toUpperCase()
        const value: string = comment.substring(eqIdx + 1)
        if (key === 'TITLE' && tags.title.length === 0) {
          tags.title = value
        } else if (key === 'ARTIST' && tags.artist.length === 0) {
          tags.artist = value
        } else if (key === 'ALBUM' && tags.album.length === 0) {
          tags.album = value
        } else if (key === 'LYRICS' && tags.lyric.length === 0) {
          tags.lyric = value
        } else if (key === 'METADATA_BLOCK_PICTURE' && tags.coverBytes === null) {
          const decoded: Uint8Array | null = TagReader.tryDecodeBase64(value)
          if (decoded !== null) {
            const p = TagReader.parseFlacPicture(decoded)
            if (p) {
              tags.coverBytes = p.bytes
              tags.coverMime = p.mime
            }
          }
        }
      }
    }
  }

  private static readFlac(fd: number): EmbeddedTags | null {
    const tags: EmbeddedTags = TagReader.emptyTags()
    // 已读 4 字节 "fLaC"，读 STREAMINFO 块头
    const blockHeader = new ArrayBuffer(4)
    fileIo.readSync(fd, blockHeader)
    const bh = new Uint8Array(blockHeader)
    let isLast: boolean = (bh[0] & 0x80) !== 0
    let blockType: number = bh[0] & 0x7F
    let blockSize: number = (bh[1] << 16) | (bh[2] << 8) | bh[3]

    if (blockType === 0 && blockSize > 0) {
      TagReader.skipBytes(fd, blockSize)
    }

    while (!isLast) {
      const nextHeader = new ArrayBuffer(4)
      fileIo.readSync(fd, nextHeader)
      const nh = new Uint8Array(nextHeader)
      isLast = (nh[0] & 0x80) !== 0
      blockType = nh[0] & 0x7F
      blockSize = (nh[1] << 16) | (nh[2] << 8) | nh[3]
      if (blockSize <= 0 || blockSize > 10 * 1024 * 1024) {
        break
      }
      if (blockType === 4) {
        TagReader.parseVorbisComment(fd, blockSize, tags)
      } else if (blockType === 6) {
        // PICTURE 块
        const picBuf = new ArrayBuffer(blockSize)
        fileIo.readSync(fd, picBuf)
        const pic = new Uint8Array(picBuf)
        const p = TagReader.parseFlacPicture(pic)
        if (p && tags.coverBytes === null) {
          tags.coverBytes = p.bytes
          tags.coverMime = p.mime
        }
      } else {
        TagReader.skipBytes(fd, blockSize)
      }
    }
    return TagReader.hasContent(tags) ? tags : null
  }

  private static parseVorbisComment(fd: number, blockSize: number, tags: EmbeddedTags): void {
    const commentData = new ArrayBuffer(blockSize)
    fileIo.readSync(fd, commentData)
    const cd = new Uint8Array(commentData)
    let offset: number = 0
    const vendorLen: number = TagReader.readUint32LE(cd, 0)
    offset = 4 + vendorLen
    if (offset + 4 > blockSize) {
      return
    }
    const commentCount: number = TagReader.readUint32LE(cd, offset)
    offset += 4
    for (let i = 0; i < commentCount && offset + 4 <= blockSize; i++) {
      const len: number = TagReader.readUint32LE(cd, offset)
      offset += 4
      if (offset + len > blockSize) {
        break
      }
      const commentBytes: Uint8Array = cd.subarray(offset, offset + len)
      offset += len
      const comment: string = TagReader.tryUtf8(commentBytes)
      const eqIdx: number = comment.indexOf('=')
      if (eqIdx > 0) {
        const key: string = comment.substring(0, eqIdx).toUpperCase()
        const value: string = comment.substring(eqIdx + 1)
        if (key === 'TITLE' && tags.title.length === 0) {
          tags.title = value
        } else if (key === 'ARTIST' && tags.artist.length === 0) {
          tags.artist = value
        } else if (key === 'ALBUM' && tags.album.length === 0) {
          tags.album = value
        } else if (key === 'LYRICS' && tags.lyric.length === 0) {
          tags.lyric = value
        } else if (key === 'METADATA_BLOCK_PICTURE' && tags.coverBytes === null) {
          const decoded: Uint8Array | null = TagReader.tryDecodeBase64(value)
          if (decoded !== null) {
            const p = TagReader.parseFlacPicture(decoded)
            if (p) {
              tags.coverBytes = p.bytes
              tags.coverMime = p.mime
            }
          }
        }
      }
    }
  }

  private static parseFlacPicture(data: Uint8Array): EmbeddedPicture | null {
    try {
      let p: number = 0
      p += 4 // 图片类型
      const mimeLen: number = TagReader.readUint32BE(data, p)
      p += 4
      if (p + mimeLen > data.length) {
        return null
      }
      const mime: string = TagReader.bytesToString(data.subarray(p, p + mimeLen)).toLowerCase()
      p += mimeLen
      const descLen: number = TagReader.readUint32BE(data, p)
      p += 4
      p += descLen
      p += 16 // 宽/高/位深/颜色数
      const dataLen: number = TagReader.readUint32BE(data, p)
      p += 4
      if (p + dataLen > data.length) {
        return null
      }
      return { bytes: data.subarray(p, p + dataLen), mime: mime }
    } catch (_e) {
      return null
    }
  }

  // ==================== 工具 ====================

  // ID3 文本帧解码（首字节为编码）
  private static decodeTextFrame(frameData: Uint8Array): string {
    if (frameData.length === 0) {
      return ''
    }
    const encoding: number = frameData[0]
    return TagReader.decodeTextBytes(frameData.subarray(1), encoding)
  }

  private static decodeTextBytes(bytes: Uint8Array, encoding: number): string {
    if (bytes.length === 0) {
      return ''
    }
    let textBytes: Uint8Array = bytes
    if (encoding === 0) {
      // ISO-8859-1 声明但中文歌曲实际为 GBK/UTF-8
      return CompatUtils.decodeResponse(textBytes)
    }
    if (encoding === 1 || encoding === 2) {
      if (encoding === 1 && textBytes.length >= 2) {
        if (textBytes[0] === 0xFF && textBytes[1] === 0xFE) {
          return TagReader.tryDecodeLabel('utf-16le', textBytes.subarray(2))
        }
        if (textBytes[0] === 0xFE && textBytes[1] === 0xFF) {
          return TagReader.tryDecodeLabel('utf-16be', textBytes.subarray(2))
        }
      }
      const le: string = TagReader.tryDecodeLabel('utf-16le', textBytes)
      if (le.length > 0 && le.indexOf('\uFFFD') < 0) {
        return le
      }
      return TagReader.tryDecodeLabel('utf-16be', textBytes)
    }
    return TagReader.tryDecodeLabel('utf-8', textBytes)
  }

  private static tryDecodeLabel(label: string, bytes: Uint8Array): string {
    try {
      const decoder: util.TextDecoder = util.TextDecoder.create(label)
      let s: string = decoder.decodeToString(bytes)
      // 去除尾部 null
      let end: number = s.length
      while (end > 0 && (s.charCodeAt(end - 1) === 0)) {
        end--
      }
      s = s.substring(0, end)
      return s
    } catch (_e) {
      return ''
    }
  }

  private static tryUtf8(bytes: Uint8Array): string {
    return TagReader.tryDecodeLabel('utf-8', bytes)
  }

  private static tryDecodeBase64(value: string): Uint8Array | null {
    try {
      const helper: util.Base64Helper = new util.Base64Helper()
      return helper.decodeSync(value)
    } catch (_e) {
      return null
    }
  }

  private static bytesToString(bytes: Uint8Array): string {
    let s: string = ''
    for (let i = 0; i < bytes.length; i++) {
      s += String.fromCharCode(bytes[i])
    }
    return s
  }

  private static readUint32LE(data: Uint8Array, offset: number): number {
    return data[offset] | (data[offset + 1] << 8) | (data[offset + 2] << 16) | (data[offset + 3] << 24)
  }

  private static readUint32BE(data: Uint8Array, offset: number): number {
    return (data[offset] << 24) | (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3]
  }

  private static skipBytes(fd: number, totalBytes: number): void {
    let remaining: number = totalBytes
    const chunkSize: number = 64 * 1024
    while (remaining > 0) {
      const readSize: number = Math.min(remaining, chunkSize)
      const buf = new ArrayBuffer(readSize)
      fileIo.readSync(fd, buf)
      remaining -= readSize
    }
  }
}

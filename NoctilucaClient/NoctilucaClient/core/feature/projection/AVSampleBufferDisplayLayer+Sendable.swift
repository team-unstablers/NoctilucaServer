//
//  AVSampleBufferDisplayLayer+Sendable.swift
//  NoctilucaClient
//
//  ProjectionSession (actor) 가 등록 / 해제 호출에서 layer 의 *reference* 만 보관하고
//  실제 enqueue 는 main actor 컨텍스트에서 일어나도록 호출 측이 보장하므로
//  layer 자체는 actor 경계를 안전하게 넘을 수 있다.
//  Swift 6 strict concurrency 에서 컴파일을 통과시키기 위한 retroactive 적합성.
//

import AVFoundation

extension AVSampleBufferDisplayLayer: @retroactive @unchecked Sendable {}

//
//  ViewController.m
//  XDXVideoDecoder
//
//  Created by 小东邪 on 2019/6/2.
//  Copyright © 2019 小东邪. All rights reserved.
//

#import "ViewController.h"
#import "XDXAVParseHandler.h"
#import "XDXFFmpegAudioDecoder.h"
#import "XDXAudioQueuePlayer.h"
#import <AVFoundation/AVFoundation.h>
#import "XDXQueueProcess.h"

// FFmpeg Header File
#ifdef __cplusplus
extern "C" {
#endif
    
#include "libavformat/avformat.h"
#include "libavcodec/avcodec.h"
#include "libavutil/avutil.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
#include "libavutil/opt.h"
    
#ifdef __cplusplus
};
#endif

int kXDXBufferSize = 4096;

@interface ViewController ()<XDXFFmpegAudioDecoderDelegate>

@property (weak, nonatomic  ) IBOutlet UIButton *startBtn;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];

    // This is only for the testPCM.caf file.
    AudioStreamBasicDescription audioFormat = {
        .mSampleRate         = 48000,
        .mFormatID           = kAudioFormatLinearPCM,
        .mChannelsPerFrame   = 2,
        .mFormatFlags        = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
        .mBitsPerChannel     = 16,
        .mBytesPerPacket     = 4,
        .mBytesPerFrame      = 4,
        .mFramesPerPacket    = 1,
    };
    
    // Configure Audio Queue Player
    [[XDXAudioQueuePlayer getInstance] configureAudioPlayerWithAudioFormat:&audioFormat bufferSize:kXDXBufferSize];
}

- (void)setupUI {
    [self.view bringSubviewToFront:self.startBtn];
}

- (IBAction)startParseDidClicked:(id)sender {
    [self startDecode];
}

- (void)startDecode {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"test" ofType:@"MOV"];
    XDXAVParseHandler *parseHandler = [[XDXAVParseHandler alloc] initWithPath:path];
    XDXFFmpegAudioDecoder *decoder = [[XDXFFmpegAudioDecoder alloc] initWithFormatContext:[parseHandler getFormatContext] audioStreamIndex:[parseHandler getAudioStreamIndex]];
    decoder.delegate = self;
    [parseHandler startParseGetAVPackeWithCompletionHandler:^(BOOL isVideoFrame, BOOL isFinish, AVPacket packet) {
        if (isFinish) {
            [decoder stopDecoder];
            return;
        }

        if (!isVideoFrame) {
            [decoder startDecodeAudioDataWithAVPacket:packet];
        }
    }];
}

#pragma mark - Decode Callback
- (void)getDecodeAudioDataByFFmpeg:(void *)data size:(int)size isFirstFrame:(BOOL)isFirstFrame {
    if (isFirstFrame) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // First put 5 frame audio data to work queue then start audio queue to read it to play.
            [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:YES block:^(NSTimer * _Nonnull timer) {
                
                XDXCustomQueueProcess *audioBufferQueue = [XDXAudioQueuePlayer getInstance]->_audioBufferQueue;
                int size = audioBufferQueue->GetQueueSize(audioBufferQueue->m_work_queue);
                if (size > 3) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[XDXAudioQueuePlayer getInstance] startAudioPlayer];
                    });
                    [timer invalidate];
                }
            }];
        });
    }
    
    // Put audio data from audio file into audio data queue
    [self addBufferToWorkQueueWithAudioData:data size:size];
    
    // control rate
    usleep(16*1000);
}

- (void)addBufferToWorkQueueWithAudioData:(void *)data  size:(int)size {
    XDXCustomQueueProcess *audioBufferQueue =  [XDXAudioQueuePlayer getInstance]->_audioBufferQueue;
    
    XDXCustomQueueNode *node = audioBufferQueue->DeQueue(audioBufferQueue->m_free_queue);
    if (node == NULL) {
        NSLog(@"XDXCustomQueueProcess addBufferToWorkQueueWithSampleBuffer : Data in , the node is NULL !");
        return;
    }
    
    node->size = size;
    memcpy(node->data, data, size);
    audioBufferQueue->EnQueue(audioBufferQueue->m_work_queue, node);
    
    NSLog(@"Test Data in ,  work size = %d, free size = %d !",audioBufferQueue->m_work_queue->size, audioBufferQueue->m_free_queue->size);
}

@end

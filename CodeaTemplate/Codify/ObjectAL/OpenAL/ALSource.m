//
//  ALSource.m
//  ObjectAL
//
//  Created by Karl Stenerud on 15/12/09.
//
// Copyright 2009 Karl Stenerud
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// Note: You are NOT required to make the license available from within your
// iOS application. Including it in your project is sufficient.
//
// Attribution is not required, but appreciated :)
//

#import "ALSource.h"
#import "ObjectALMacros.h"
#import "ALWrapper.h"
#import "OpenALManager.h"
#import "OALAudioActions.h"
#import "OALUtilityActions.h"


#pragma mark -
#pragma mark Private Methods

/**
 * (INTERNAL USE) Private methods for ALSource.
 */
@interface ALSource (Private)

/** (INTERNAL USE) Close any resources belonging to the OS.
 */
- (void) closeOSResources;

/** (INTERNAL USE) Called by SuspendHandler.
 */
- (void) setSuspended:(bool) value;

/** (INTERNAL USE) Callback for resuming playback after delay to
 * get around OpenAL bug.
 */
- (void) delayedResumePlayback;


@end


@implementation ALSource

#pragma mark Object Management

+ (id) source
{
	return [[[self alloc] init] autorelease];
}

+ (id) sourceOnContext:(ALContext*) context
{
	return [[[self alloc] initOnContext:context] autorelease];
}

- (id) init
{
	return [self initOnContext:[OpenALManager sharedInstance].currentContext];
}

- (id) initOnContext:(ALContext*) contextIn
{
	if(nil != (self = [super init]))
	{
		OAL_LOG_DEBUG(@"%@: Init on context %@", self, contextIn);

		if(nil == contextIn)
		{
			OAL_LOG_ERROR(@"%@: Failed to init because context was nil. Returning nil", self);
			[self release];
			return nil;
		}
		
		suspendHandler = [[OALSuspendHandler alloc] initWithTarget:self selector:@selector(setSuspended:)];

		context = [contextIn retain];
		@synchronized([OpenALManager sharedInstance])
		{
			ALContext* realContext = [OpenALManager sharedInstance].currentContext;
			[OpenALManager sharedInstance].currentContext = context;
			sourceId = [ALWrapper genSource];
			[OpenALManager sharedInstance].currentContext = realContext;
		}
		OAL_LOG_DEBUG(@"%@: Created source %08x", self, sourceId);

		[context notifySourceInitializing:self];
		gain = [ALWrapper getSourcef:sourceId parameter:AL_GAIN];
		
		[context addSuspendListener:self];
	}
	return self;
}

- (void) dealloc
{
	OAL_LOG_DEBUG(@"%@: Dealloc, sourceId = %08x", self, sourceId);

	[context removeSuspendListener:self];
	[context notifySourceDeallocating:self];

	[self closeOSResources];
	
	[gainAction stopAction];
	[gainAction release];
	[panAction stopAction];
	[panAction release];
	[pitchAction stopAction];
	[pitchAction release];
	[suspendHandler release];
	[context release];

	// In IOS 3.x, OpenAL doesn't stop playing right away.
	// Release after a delay to give it some time to stop.
	[buffer performSelector:@selector(release) withObject:nil afterDelay:0.1];
	
	[super dealloc];
}

- (void) closeOSResources
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if((ALuint)AL_INVALID != sourceId)
		{
			[ALWrapper sourceStop:sourceId];
			[ALWrapper sourcei:sourceId parameter:AL_BUFFER value:AL_NONE];
			
			@synchronized([OpenALManager sharedInstance])
			{
				ALContext* realContext = [OpenALManager sharedInstance].currentContext;
				if(realContext != context)
				{
					// Make this source's context the current one if it isn't already.
					[OpenALManager sharedInstance].currentContext = context;
				}

				[ALWrapper deleteSource:sourceId];
				
				[OpenALManager sharedInstance].currentContext = realContext;
			}
			sourceId = (ALuint)AL_INVALID;
		}
	}
}

- (void) close
{
	[self closeOSResources];
}


#pragma mark Properties

- (ALBuffer*) buffer
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return buffer;
	}
}

- (void) setBuffer:(ALBuffer *) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
			
		[self stop];

		// In IOS 3.x, OpenAL doesn't stop playing right away.
		// Release after a delay to give it some time to stop.
		[buffer performSelector:@selector(release) withObject:nil afterDelay:0.1];

		buffer = [value retain];
		[ALWrapper sourcei:sourceId parameter:AL_BUFFER value:buffer.bufferId];
	}
}

- (int) buffersQueued
{
	return [ALWrapper getSourcei:sourceId parameter:AL_BUFFERS_QUEUED];
}

- (int) buffersProcessed
{
	return [ALWrapper getSourcei:sourceId parameter:AL_BUFFERS_PROCESSED];
}

- (float) coneInnerAngle
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return [ALWrapper getSourcef:sourceId parameter:AL_CONE_INNER_ANGLE];
	}
}

- (void) setConeInnerAngle:(float) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[ALWrapper sourcef:sourceId parameter:AL_CONE_INNER_ANGLE value:value];
	}
}

- (float) coneOuterAngle
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return [ALWrapper getSourcef:sourceId parameter:AL_CONE_OUTER_ANGLE];
	}
}

- (void) setConeOuterAngle:(float) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[ALWrapper sourcef:sourceId parameter:AL_CONE_OUTER_ANGLE value:value];
	}
}

- (float) coneOuterGain
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return [ALWrapper getSourcef:sourceId parameter:AL_CONE_OUTER_GAIN];
	}
}

- (void) setConeOuterGain:(float) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[ALWrapper sourcef:sourceId parameter:AL_CONE_OUTER_GAIN value:value];
	}
}

@synthesize context;

- (ALVector) direction
{
	ALVector result;
	OPTIONALLY_SYNCHRONIZED(self)
	{
		[ALWrapper getSource3f:sourceId parameter:AL_DIRECTION v1:&result.x v2:&result.y v3:&result.z];
	}
	return result;
}

- (void) setDirection:(ALVector) value
{
	OPTIONALLY_SYNCHRONIZED_STRUCT_OP(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[ALWrapper source3f:sourceId parameter:AL_DIRECTION v1:value.x v2:value.y v3:value.z];
	}
}

- (float) volume
{
	return self.gain;
}

- (void) setVolume:(float) value
{
	self.gain = value;
}

- (float) gain
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return gain;
	}
}

- (void) setGain:(float) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		gain = value;
		if(muted)
		{
			value = 0;
		}
		[ALWrapper sourcef:sourceId parameter:AL_GAIN value:value];
	}
}

@synthesize interruptible;

- (bool) looping
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return [ALWrapper getSourcei:sourceId parameter:AL_LOOPING];
	}
}

- (void) setLooping:(bool) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[ALWrapper sourcei:sourceId parameter:AL_LOOPING value:value];
	}
}

- (float) maxDistance
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return [ALWrapper getSourcef:sourceId parameter:AL_MAX_DISTANCE];
	}
}

- (void) setMaxDistance:(float) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[ALWrapper sourcef:sourceId parameter:AL_MAX_DISTANCE value:value];
	}
}

- (float) maxGain
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return [ALWrapper getSourcef:sourceId parameter:AL_MAX_GAIN];
	}
}

- (void) setMaxGain:(float) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[ALWrapper sourcef:sourceId parameter:AL_MAX_GAIN value:value];
	}
}

- (float) minGain
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return [ALWrapper getSourcef:sourceId parameter:AL_MIN_GAIN];
	}
}

- (void) setMinGain:(float) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[ALWrapper sourcef:sourceId parameter:AL_MIN_GAIN value:value];
	}
}

- (bool) muted
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return muted;
	}
}

- (void) setMuted:(bool) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		muted = value;
		if(muted)
		{
			[self stopActions];
		}
		// Force a re-evaluation of gain.
		[self setGain:gain];
	}
}

- (float) offsetInBytes
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return [ALWrapper getSourcef:sourceId parameter:AL_BYTE_OFFSET];
	}
}

- (void) setOffsetInBytes:(float) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[ALWrapper sourcef:sourceId parameter:AL_BYTE_OFFSET value:value];
	}
}

- (float) offsetInSamples
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return [ALWrapper getSourcef:sourceId parameter:AL_SAMPLE_OFFSET];
	}
}

- (void) setOffsetInSamples:(float) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[ALWrapper sourcef:sourceId parameter:AL_SAMPLE_OFFSET value:value];
	}
}

- (float) offsetInSeconds
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return [ALWrapper getSourcef:sourceId parameter:AL_SEC_OFFSET];
	}
}

- (void) setOffsetInSeconds:(float) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[ALWrapper sourcef:sourceId parameter:AL_SEC_OFFSET value:value];
	}
}

- (bool) paused
{
	if(self.suspended)
	{
		return AL_PAUSED == shadowState;
	}

	return AL_PAUSED == self.state;
}

- (void) setPaused:(bool) shouldPause
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		int newState = 0;
		
		if(shouldPause)
		{
			abortPlaybackResume = YES;
			newState = AL_PAUSED;
			if(AL_PLAYING == self.state)
			{
				if(![ALWrapper sourcePause:sourceId])
				{
					newState = 0;
				}
			}
		}
		else
		{
			newState = AL_PLAYING;
			if(AL_PAUSED == self.state)
			{
				if(![ALWrapper sourcePlay:sourceId])
				{
					newState = AL_STOPPED;
				}
			}
		}
		
		if(0 != newState)
		{
			shadowState = newState;
		}
	}
}

- (float) pitch
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return [ALWrapper getSourcef:sourceId parameter:AL_PITCH];
	}
}

- (void) setPitch:(float) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[ALWrapper sourcef:sourceId parameter:AL_PITCH value:value];
	}
}

- (bool) playing
{
	if(self.suspended)
	{
		return AL_PLAYING == shadowState || AL_PAUSED == shadowState;
	}
	return AL_PLAYING == self.state || AL_PAUSED == self.state;
}

- (ALPoint) position
{
	ALPoint result;
	OPTIONALLY_SYNCHRONIZED(self)
	{
		[ALWrapper getSource3f:sourceId parameter:AL_POSITION v1:&result.x v2:&result.y v3:&result.z];
	}
	return result;
}

- (void) setPosition:(ALPoint) value
{
	OPTIONALLY_SYNCHRONIZED_STRUCT_OP(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[ALWrapper source3f:sourceId parameter:AL_POSITION v1:value.x v2:value.y v3:value.z];
	}
}

- (float) pan
{
	return self.position.x;
}

- (void) setPan:(float) value
{
	if(self.suspended)
	{
		OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
		return;
	}
	
	self.position = alpoint(value, 0, 0);
}

- (float) referenceDistance
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return [ALWrapper getSourcef:sourceId parameter:AL_REFERENCE_DISTANCE];
	}
}

- (void) setReferenceDistance:(float) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[ALWrapper sourcef:sourceId parameter:AL_REFERENCE_DISTANCE value:value];
	}
}

- (float) rolloffFactor
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return [ALWrapper getSourcef:sourceId parameter:AL_ROLLOFF_FACTOR];
	}
}

- (void) setRolloffFactor:(float) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[ALWrapper sourcef:sourceId parameter:AL_ROLLOFF_FACTOR value:value];
	}
}

@synthesize sourceId;

- (int) sourceRelative
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return [ALWrapper getSourcei:sourceId parameter:AL_SOURCE_RELATIVE];
	}
}

- (void) setSourceRelative:(int) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[ALWrapper sourcei:sourceId parameter:AL_SOURCE_RELATIVE value:value];
	}
}

- (int) sourceType
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return [ALWrapper getSourcei:sourceId parameter:AL_SOURCE_TYPE];
	}
}

- (void) setSourceType:(int) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[ALWrapper sourcei:sourceId parameter:AL_SOURCE_TYPE value:value];
	}
}

- (int) state
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		// Apple's OpenAL implementation is broken.
		//return [ALWrapper getSourcei:sourceId parameter:AL_SOURCE_STATE];
		
		if(AL_INITIAL == shadowState || AL_STOPPED == shadowState)
		{
			return shadowState;
		}
		if(AL_STOPPED == [ALWrapper getSourcei:sourceId parameter:AL_SOURCE_STATE])
		{
			return AL_STOPPED;
		}
		return shadowState;
	}
}

- (void) setState:(int) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[ALWrapper sourcei:sourceId parameter:AL_SOURCE_STATE value:value];
		shadowState = value;
	}
}

- (ALVector) velocity
{
	ALVector result;
	OPTIONALLY_SYNCHRONIZED(self)
	{
		[ALWrapper getSource3f:sourceId parameter:AL_VELOCITY v1:&result.x v2:&result.y v3:&result.z];
	}
	return result;
}

- (void) setVelocity:(ALVector) value
{
	OPTIONALLY_SYNCHRONIZED_STRUCT_OP(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[ALWrapper source3f:sourceId parameter:AL_VELOCITY v1:value.x v2:value.y v3:value.z];
	}
}



#pragma mark Suspend Handler

- (void) addSuspendListener:(id<OALSuspendListener>) listenerIn
{
	[suspendHandler addSuspendListener:listenerIn];
}

- (void) removeSuspendListener:(id<OALSuspendListener>) listenerIn
{
	[suspendHandler removeSuspendListener:listenerIn];
}

- (bool) manuallySuspended
{
	return suspendHandler.manuallySuspended;
}

- (void) setManuallySuspended:(bool) value
{
	suspendHandler.manuallySuspended = value;
}

- (bool) interrupted
{
	return suspendHandler.interrupted;
}

- (void) setInterrupted:(bool) value
{
	suspendHandler.interrupted = value;
}

- (bool) suspended
{
	return suspendHandler.suspended;
}

- (void) setSuspended:(bool) value
{
	if(value)
	{
		shadowState = self.state;
		if(AL_PLAYING == shadowState)
		{
			[ALWrapper sourcePause:sourceId];
		}
	}
	else
	{
		// The shadow state holds the state we had when suspending.
		if(AL_PLAYING == shadowState)
		{
			// Because Apple's OpenAL implementation can't stack commands (it defers processing
			// to a later sequence point), we have to delay resuming playback.
			abortPlaybackResume = NO;
			[self performSelector:@selector(delayedResumePlayback) withObject:nil afterDelay:0.03];
		}
	}
}

- (void) delayedResumePlayback
{
	if(!abortPlaybackResume)
	{
		[ALWrapper sourcePlay:sourceId];
	}
}


#pragma mark Playback

- (void) preload:(ALBuffer*) bufferIn
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[self stopActions];

		if(self.playing || self.paused)
		{
			[self stop];
		}
	
		self.buffer = bufferIn;
	}
}

- (id<ALSoundSource>) play
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return nil;
		}
		
		[self stopActions];

		if(self.playing)
		{
			if(!interruptible)
			{
				return nil;
			}
			[self stop];
		}
		
		if(self.paused)
		{
			[self stop];
		}
		
		if([ALWrapper sourcePlay:sourceId])
		{
			shadowState = AL_PLAYING;
		}
		else
		{
			shadowState = AL_STOPPED;
		}
	}
	return self;
}

- (id<ALSoundSource>) play:(ALBuffer*) bufferIn
{
	return [self play:bufferIn loop:NO];
}

- (id<ALSoundSource>) play:(ALBuffer*) bufferIn loop:(bool) loop
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return nil;
		}
		
		[self stopActions];

		if(self.playing)
		{
			if(!interruptible)
			{
				return nil;
			}
			[self stop];
		}
		
		self.buffer = bufferIn;
		self.looping = loop;
		
		if([ALWrapper sourcePlay:sourceId])
		{
			shadowState = AL_PLAYING;
		}
		else
		{
			shadowState = AL_STOPPED;
		}
	}
	return self;
}

- (id<ALSoundSource>) play:(ALBuffer*) bufferIn gain:(float) gainIn pitch:(float) pitchIn pan:(float) panIn loop:(bool) loopIn
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return nil;
		}
		
		[self stopActions];

		if(self.playing)
		{
			if(!interruptible)
			{
				return nil;
			}
			[self stop];
		}
		
		self.buffer = bufferIn;
		
		// Set gain, pitch, and pan
		self.gain = gainIn;
		self.pitch = pitchIn;
		self.pan = panIn;
		self.looping = loopIn;
		
		if([ALWrapper sourcePlay:sourceId])
		{
			shadowState = AL_PLAYING;
		}
		else
		{
			shadowState = AL_STOPPED;
		}
	}		
	return self;
}

- (void) stop
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		abortPlaybackResume = YES;
		[self stopActions];
		[ALWrapper sourceStop:sourceId];
		shadowState = AL_STOPPED;
	}
}

- (void) rewind
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		abortPlaybackResume = YES;
		[self stopActions];
		[ALWrapper sourceRewind:sourceId];
		shadowState = AL_INITIAL;
	}
}

- (void) fadeTo:(float) value
	   duration:(float) duration
		 target:(id) target
	   selector:(SEL) selector
{
	// Must always be synchronized
	@synchronized(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[self stopFade];
		gainAction = [[OALSequentialActions actions:
					   [OALGainAction actionWithDuration:duration endValue:value],
					   [OALCallAction actionWithCallTarget:target selector:selector withObject:self],
					   nil] retain];
		[gainAction runWithTarget:self];
	}
}

- (void) stopFade
{
	// Must always be synchronized
	@synchronized(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[gainAction stopAction];
		[gainAction release];
		gainAction = nil;
	}
}

- (void) panTo:(float) value
	   duration:(float) duration
		 target:(id) target
	   selector:(SEL) selector
{
	// Must always be synchronized
	@synchronized(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[self stopPan];
		gainAction = [[OALSequentialActions actions:
					   [OALPanAction actionWithDuration:duration endValue:value],
					   [OALCallAction actionWithCallTarget:target selector:selector withObject:self],
					   nil] retain];
		[gainAction runWithTarget:self];
	}
}

- (void) stopPan
{
	// Must always be synchronized
	@synchronized(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[gainAction stopAction];
		[gainAction release];
		gainAction = nil;
	}
}

- (void) pitchTo:(float) value
	  duration:(float) duration
		target:(id) target
	  selector:(SEL) selector
{
	// Must always be synchronized
	@synchronized(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[self stopPitch];
		gainAction = [[OALSequentialActions actions:
					   [OALPitchAction actionWithDuration:duration endValue:value],
					   [OALCallAction actionWithCallTarget:target selector:selector withObject:self],
					   nil] retain];
		[gainAction runWithTarget:self];
	}
}

- (void) stopPitch
{
	// Must always be synchronized
	@synchronized(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		[gainAction stopAction];
		[gainAction release];
		gainAction = nil;
	}
}

- (void) stopActions
{
	[self stopFade];
	[self stopPan];
	[self stopPitch];
}

- (void) clear
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		self.manuallySuspended = NO;
		[self stop];
		self.buffer = nil;
	}
}


#pragma mark Queued Playback

- (bool) queueBuffer:(ALBuffer*) bufferIn
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return NO;
		}
		
		if(AL_STATIC == self.state)
		{
			self.buffer = nil;
		}
		ALuint bufferId = bufferIn.bufferId;
		return [ALWrapper sourceQueueBuffers:sourceId numBuffers:1 bufferIds:&bufferId];
	}
}

- (bool) queueBuffers:(NSArray*) buffers
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return NO;
		}
		
		if(AL_STATIC == self.state)
		{
			self.buffer = nil;
		}
		int numBuffers = [buffers count];
		ALuint* bufferIds = (ALuint*)malloc(sizeof(ALuint) * numBuffers);
		int i = 0;
		for(ALBuffer* buf in buffers)
		{
			bufferIds[i] = buf.bufferId;
		}
		bool result = [ALWrapper sourceQueueBuffers:sourceId numBuffers:numBuffers bufferIds:bufferIds];
		free(bufferIds);
		return result;
	}
}

- (bool) unqueueBuffer:(ALBuffer*) bufferIn
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return NO;
		}
		
		ALuint bufferId = bufferIn.bufferId;
		return [ALWrapper sourceUnqueueBuffers:sourceId numBuffers:1 bufferIds:&bufferId];
	}
}

- (bool) unqueueBuffers:(NSArray*) buffers
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.suspended)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return NO;
		}
		
		if(AL_STATIC == self.state)
		{
			self.buffer = nil;
		}
		int numBuffers = [buffers count];
		ALuint* bufferIds = malloc(sizeof(ALuint) * numBuffers);
		int i = 0;
		for(ALBuffer* buf in buffers)
		{
			bufferIds[i] = buf.bufferId;
		}
		bool result = [ALWrapper sourceUnqueueBuffers:sourceId numBuffers:numBuffers bufferIds:bufferIds];
		free(bufferIds);
		return result;
	}
}

#pragma mark Internal Use

- (bool) requestUnreserve:(bool) interrupt
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(self.playing)
		{
			if(!self.interruptible || !interrupt)
			{
				return NO;
			}
			[self stop];
		}
		self.buffer = nil;
	}
	return YES;
}


@end

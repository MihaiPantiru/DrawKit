/**
 @author Contributions from the community; see CONTRIBUTORS.md
 @date 2005-2016
 @copyright MPL2; see LICENSE.txt
*/

#import "DKObjectCreationTool.h"
#import "DKObjectDrawingLayer.h"
#import "DKDrawablePath.h"
#import "DKDrawing.h"
#import "DKStyle.h"
#import "DKStyleRegistry.h"
#import "DKToolController.h"
#import "DKSelectAndEditTool.h"
#import "LogEvent.h"
#import "DKTextShape.h"

#pragma mark Contants(Non - localized)
NSString* kDKDrawingToolWillMakeNewObjectNotification = @"kDKDrawingToolWillMakeNewObjectNotification";
NSString* kDKDrawingToolCreatedObjectsStyleDidChange = @"kDKDrawingToolCreatedObjectsStyleDidChange";

#pragma mark Static Vars
static DKStyle* sCreatedObjectsStyle = nil;

@interface DKObjectCreationTool (Private)

- (BOOL)finishCreation:(DKToolController*)controller;

@end

#pragma mark -
@implementation DKObjectCreationTool
#pragma mark As a DKObjectCreationTool

/** @brief Create a tool for an existing object

 This method conveniently allows you to create tools for any object you already have. For example
 if you create a complex shape from others, or make a group of objects, you can turn that object
 into an interactive tool to make more of the same.
 @param shape a drawable object that can be created by the tool - typically a DKDrawableShape
 @param name the name of the tool to register this with
 */

- (id)init {
    self = [super init];
    if (self != nil) {
        mProxyDragThreshold = kDKSelectToolDefaultProxyDragThreshold;
    }
    
    return self;
}

+ (void)registerDrawingToolForObject:(id<NSCopying>)shape withName:(NSString*)name
{
	// creates a drawing tool for the given object and registers it with the name. This quickly allows you to make a tool
	// for any object you already have, give it a name and use it to make more similar objects in the drawing.

	NSAssert(shape != nil, @"trying to make a tool for nil shape");

	id cpy = [shape copyWithZone:nil];
	DKObjectCreationTool* dt = [[[DKObjectCreationTool alloc] initWithPrototypeObject:cpy] autorelease];
	[cpy release];

	[DKDrawingTool registerDrawingTool:dt
							  withName:name];
}

/** @brief Set a style to be used for subsequently created objects

 If you set nil, the style set in the prototype object for the individual tool will be used instead.
 @param aStyle a style object that will be applied to each new object as it is created
 */
+ (void)setStyleForCreatedObjects:(DKStyle*)aStyle
{
	if (![aStyle isEqualToStyle:sCreatedObjectsStyle]) {
		//NSLog(@"setting style for created objects = '%@'", [aStyle name]);

		[aStyle retain];
		[sCreatedObjectsStyle release];
		sCreatedObjectsStyle = aStyle;
		[[NSNotificationCenter defaultCenter] postNotificationName:kDKDrawingToolCreatedObjectsStyleDidChange
															object:self];
	}
}

/** @brief Return a style to be used for subsequently created objects

 If you set nil, the style set in the prototype object for the individual tool will be used instead.
 @return a style object that will be applied to each new object as it is created, or nil
 */
+ (DKStyle*)styleForCreatedObjects
{
	return sCreatedObjectsStyle;
}

#pragma mark -

/** @brief Initialize the tool
 @param aPrototype an object that will be used as the tool's prototype - each new object created will
 @return the tool object
 */
- (id)initWithPrototypeObject:(id<NSObject>)aPrototype {
	self = [super init];
	if (self != nil) {
		[self setPrototype:aPrototype];
		[self setStylePickupEnabled:YES];

		if (m_prototypeObject == nil) {
			[self autorelease];
			self = nil;
		}
	}
	return self;
}

#pragma mark -

/** @brief Set the object to be copied when the tool created a new one
 @param aPrototype an object that will be used as the tool's prototype - each new object created will
 */
- (void)setPrototype:(id<NSObject>)aPrototype
{
	NSAssert(aPrototype != nil, @"prototype object cannot be nil");

	[aPrototype retain];
	[m_prototypeObject release];
	m_prototypeObject = aPrototype;
}

/** @brief Return the object to be copied when the tool creates a new one
 @return an object - each new object created will be a copy of this one.
 */
- (id)prototype
{
	return m_prototypeObject;
}

/** @brief Return a new object copied from the prototype, but with the current class style if there is one

 The returned object is autoreleased
 @return a new object based on the prototype.
 */
- (id)objectFromPrototype
{
	[[NSNotificationCenter defaultCenter] postNotificationName:kDKDrawingToolWillMakeNewObjectNotification
														object:self];

	id obj = [[[self prototype] copy] autorelease];

	NSAssert(obj != nil, @"couldn't create new object from prototype");

	// if there is a class setting for a style, set it. Otherwise use the prototype's style.

	if ([obj isKindOfClass:[DKDrawableObject class]]) {
		if ([[self class] styleForCreatedObjects] != nil) {
			[(DKDrawableObject*)obj setStyle:[[self class] styleForCreatedObjects]];
		}
	}
	return obj;
}

- (void)setStyle:(DKStyle*)aStyle
{
	// sets the style for the prototype (an dhence subsequently created objects). This setting is overridden by
	// a style set for the class as a whole.

	if ([[self prototype] respondsToSelector:_cmd])
		[(DKDrawableObject*)[self prototype] setStyle:aStyle];
}

- (DKStyle*)style
{
	// returns the style that will be used by this tool. That is the prototype's style or the general style applied by the class.

	if ([[self class] styleForCreatedObjects] != nil)
		return [[self class] styleForCreatedObjects];
	else
		return [(DKDrawableObject*)[self prototype] style];
}

- (void)setStylePickupEnabled:(BOOL)pickup
{
	mEnableStylePickup = pickup;
}

- (BOOL)stylePickupEnabled
{
	return mEnableStylePickup;
}

#pragma mark -

/** @brief Return an image showing what the tool creates

 The image may be used as an icon for this tool in a UI, for example
 @return an image
 */
- (NSImage*)image
{
	return [[self prototype] swatchImageWithSize:kDKDefaultToolSwatchSize];
}

/** @brief Complete the object creation cleanly
 @return YES if undo task generated, NO otherwise
 */
- (BOOL)finishCreation:(DKToolController*)controller
{
	BOOL result = NO;

	if (m_protoObject) {
		DKObjectOwnerLayer* layer = (DKObjectOwnerLayer*)[controller activeLayer];

		// let the object know we are finishing, whether it is valid or not
		@try
		{
			[m_protoObject mouseUpAtPoint:mLastPoint
								   inPart:mPartcode
									event:[NSApp currentEvent]];
			[m_protoObject creationTool:self
				 willEndCreationAtPoint:mLastPoint];
		}
		@catch (NSException* e)
		{
			[m_protoObject release];
			m_protoObject = nil;
		}

		// if the object created is not valid, the pending add to the layer needs to be
		// aborted. Otherwise the object is committed to the layer

		if (![m_protoObject objectIsValid]) {
			[layer removePendingObject];
			LogEvent_(kReactiveEvent, @"object invalid - not committed to layer");
			result = NO;

			// should be unnecessary as undo disabled while tool creating, but in case code turned it on...

			[[layer undoManager] removeAllActionsWithTarget:m_protoObject];

			[m_protoObject release];
			m_protoObject = nil;

			// turn undo back on

			if (![[layer undoManager] isUndoRegistrationEnabled])
				[[layer undoManager] enableUndoRegistration];
		} else {
			// a valid object was made, so commit it to the layer and select it
			// turn undo back on and commit the object

			if (![[layer undoManager] isUndoRegistrationEnabled])
				[[layer undoManager] enableUndoRegistration];

			[controller toolWillPerformUndoableAction:self];

			[(DKObjectDrawingLayer*)layer recordSelectionForUndo];
			[(DKObjectDrawingLayer*)layer commitPendingObjectWithUndoActionName:[self actionName]];
			[(DKObjectDrawingLayer*)layer replaceSelectionWithObject:m_protoObject];
			[(DKObjectDrawingLayer*)layer commitSelectionUndoWithActionName:[self actionName]];

			LogEvent_(kReactiveEvent, @"object OK - committed to layer");

			[m_protoObject release];
			m_protoObject = nil;

			result = YES;
            
//            if ([m_prototypeObject isKindOfClass:[DKTextShape class]]) {
//                [[NSNotificationCenter defaultCenter] postNotificationName:@"DKDrawKitObjectCreated" object:nil];
//            }
		}
	}

	return result;
}

#pragma mark -
#pragma mark As an NSObject

/** @brief Deallocate the tool
 */
- (void)dealloc
{
	[m_prototypeObject release];
	[super dealloc];
}

#pragma mark -
#pragma mark - As a DKDrawingTool

/** @brief The tool can return arbitrary persistent data that will be stored in the prefs and returned on
 the next launch.

 If the tool has a set style, it is archived and returned so that it can be restored to the same
 style next session.
 @return data, or nil
 */
- (NSData*)persistentData
{
	if ([self style])
		return [NSKeyedArchiver archivedDataWithRootObject:[self style]];
	else
		return nil;
}

/** @brief On launch, the data that was saved by the previous session will be reloaded
 */
- (void)shouldLoadPersistentData:(NSData*)data
{
	NSAssert(data != nil, @"data was nil");

	@try
	{
		DKStyle* aStyle = [NSKeyedUnarchiver unarchiveObjectWithData:data];

		if (aStyle) {
			// this style may be registered, which means we must merge it with the registry correctly

			if ([aStyle requiresRemerge]) {
				NSSet* set = [NSSet setWithObject:aStyle];
				set = [DKStyleRegistry mergeStyles:set
									  inCategories:nil
										   options:kDKReturnExistingStyles
									 mergeDelegate:nil];

				aStyle = [set anyObject];
				[aStyle clearRemergeFlag];
			}

			//NSLog(@"restoring style '%@' to '%@'", [aStyle name], [self registeredName]);

			[self setStyle:aStyle];
		}
	}
	@catch (NSException* excp)
	{
//		NSLog(@"Tool '%@' was unable to load the style - will use default. Exception: %@", [self registeredName], excp);

		// ignore exception
	}
}

/** @brief Clean up when tool is switched out
 @param aController the tool controller
 */
- (void)toolControllerWillUnsetTool:(DKToolController*)aController
{
	//NSLog(@"unsetting %@, proto = %@", self, m_protoObject);

	[self finishCreation:aController];
}

#pragma mark -
#pragma mark - As part of DKDrawingTool Protocol

/** @brief Does the tool ever implement undoable actions?

 Returning YES means that the tool can POTENTIALLY do undoable things, not that it always will.
 @return always returns YES
 */
+ (BOOL)toolPerformsUndoableAction
{
	return YES;
}

/** @brief Return a string representing what the tool did

 The registered name of the tool is assumed to be descriptive of the objects it creates, for example
 "Rectangle", thus this returns "New Rectangle"
 @return a string
 */
- (NSString*)actionName
{
	NSString* objectName = [self registeredName];
	NSString* s = [NSString stringWithFormat:@"New %@", objectName];
	return NSLocalizedString(s, @"undo string for new object (type)");
}

/** @brief Return the tool's cursor
 @return the cross-hair cursor
 */
- (NSCursor*)cursor {
    NSString *resourcePath = [[NSBundle mainBundle] pathForResource:@"brush" ofType:@"tiff"];
    if ([m_prototypeObject isKindOfClass:[DKTextShape class]]) {
        resourcePath = [[NSBundle mainBundle] pathForResource:@"text" ofType:@"tiff"];
    }
    
    NSImage *brushImage = [[NSImage alloc] initWithContentsOfFile:resourcePath];
    NSSize brushImageSize = [brushImage size];
    NSCursor *brushCursor = [[NSCursor alloc] initWithImage:brushImage hotSpot:NSMakePoint(0.0f, brushImageSize.height - 2.0)];
    return brushCursor;
}

/** @brief Handle the initial mouse down

 Starts the creation of an object by copying the prototype and adding it to the layer as a pending
 object (pending objects are only committed if they are valid after being created). As a side-effect
 this turns off undo registration temporarily as the initial sizing of the object has no benefit
 being undone. Note that for some object types, like paths, the object will keep control in their
 own loop for the entire creation process, finally posting a mouseUp in the original view so that
 the finalising procedure is carried out.
 @param p the local point where the mouse went down
 @param obj the target object, if there is one
 @param layer the layer in which the tool is being applied
 @param event the original event
 @param aDel an optional delegate
 @return the partcode of object nominated by its class for creating instances of itself interactively
 */
- (NSInteger)mouseDownAtPoint:(NSPoint)p targetObject:(DKDrawableObject*)obj layer:(DKLayer*)layer event:(NSEvent*)event delegate:(id)aDel
{
#pragma unused(aDel)
	NSAssert(layer != nil, @"layer in creation tool mouse down was nil");

	mPartcode = kDKDrawingNoPart;
	mDidPickup = NO;
	m_protoObject = nil;
    mAnchorPoint = mLastPoint = p;
    mPerformedUndoableTask = NO;
    mMouseMoved = NO;
    
    DKObjectDrawingLayer* odl = (DKObjectDrawingLayer*)layer;

	// sanity check the layer type - in practice it shouldn't ever be anything else as this is also checked by the tool controller.

	if ([layer isKindOfClass:[DKObjectOwnerLayer class]]) {
		// this tool may do a style pickup if enabled. This allows a command-click to choose the style of the clicked object
//		BOOL pickUpStyle = (obj != nil) && [self stylePickupEnabled] && (([event modifierFlags] & NSCommandKeyMask) != 0);
//
//		if (pickUpStyle) {
//			DKStyle* style = [obj style];
//			[self setStyle:style];
//			mDidPickup = YES;
//			return mPartcode;
//		}

        
        
        // mihai.pantiru: If object selected prevent draw something else
        if (obj && ![obj isKindOfClass:[DKDrawablePath class]]) {
            
//            if ([obj locked] || [obj locationLocked]) {
//                [self setOperationMode:kDKEditToolSelectionMode];
//                mAnchorPoint = mLastPoint = p;
////                mMarqueeRect = NSRectFromTwoPoints(p, p);
//                
//                NSDictionary* userInfoDict = [NSDictionary dictionaryWithObjectsAndKeys:layer, kDKSelectionToolTargetLayer, obj, kDKSelectionToolTargetObject, nil];
//
//                [[NSNotificationCenter defaultCenter] postNotificationName:kDKSelectionToolWillStartSelectionDrag
//                                                                    object:self
//                                                                  userInfo:userInfoDict];
//                [self changeSelectionWithTarget:obj
//                                        inLayer:odl
//                                          event:event];
////                mWasInLockedObject = YES;
//                return kDKDrawingEntireObjectPart;
//            }
            
            mPartcode = [obj hitPart:p];
            
            // detect a double-click and call the target object's method for fielding it
            if ([event clickCount] > 1) {
                [obj mouseDoubleClickedAtPoint:p
                                        inPart:mPartcode
                                         event:event];
                return mPartcode;
            }
            
            
            [self changeSelectionWithTarget:obj
                                    inLayer:odl
                                      event:event];
          
            
            [self setOperationMode:kDKEditToolEditObjectMode];
            [odl replaceSelectionWithObject:obj];
            
            
            // notify we are about to start:
            
            NSDictionary* userInfoDict = [NSDictionary dictionaryWithObjectsAndKeys:layer, kDKSelectionToolTargetLayer, obj, kDKSelectionToolTargetObject, nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:kDKSelectionToolWillStartEditingObject
                                                                object:self
                                                              userInfo:userInfoDict];
            
            // setting nil here will cause the action name to be supplied by the object itself
            
            [self setUndoAction:nil];
            [obj mouseDownAtPoint:p
                           inPart:mPartcode
                            event:event];
            
             //NSLog(@"drawkit -  mpartcode %ld creationTool mouse down here obj:%@", (long)mPartcode, obj);
            
            return mPartcode;
        }

        [odl deselectAll];

         [self setOperationMode:kDKEditToolInvalidMode];
        
		// because this tool creates new objects, ignore the <obj> parameter and just make a new one
		if (m_protoObject == nil)
			m_protoObject = [[self objectFromPrototype] retain];

		NSAssert(m_protoObject != nil, @"creation tool couldn't create object from prototype");

		// turn off recording of undo until we commit the object

		[[layer undoManager] disableUndoRegistration];

		@try
		{
			// the object is initially added as a pending object - this allows it to be created without making undo tasks for
			// the layer being added to. If the creation subsequently fails, the pending object can be discarded and the layer state
			// remains as it was before.

			[(DKObjectOwnerLayer*)layer addObjectPendingCreation:m_protoObject];

			// align mouse click to the grid/guides - note, no point checking for ctrl key at this point as mouseDown + ctrl = right click -> menu
			// thus we just accept the current setting for grid snapping applied to the drawing as a whole

			p = [m_protoObject snappedMousePoint:p
				forSnappingPointsWithControlFlag:NO];

			// set the object's initial size and position (zero size, at the mouse point)
			// the call below to the object's mouseDown method will set up the drag anchoring and offset as needed

			LogEvent_(kReactiveEvent, @"creating object %@ at: %@", [m_protoObject description], NSStringFromPoint(p));

			[m_protoObject setLocation:p];
			[m_protoObject setSize:NSZeroSize];

			// let the object know we are about to start:

			[m_protoObject creationTool:self
				willBeginCreationAtPoint:p];

			// object creation starts by dragging some part - the object class can tell us what part to use here, we shouldn't
			// rely on hit-testing it directly because the result can be ambiguous for such a small object size:

			mPartcode = [[m_protoObject class] initialPartcodeForObjectCreation];
			[m_protoObject mouseDownAtPoint:p
									 inPart:mPartcode
									  event:event];
		}
		@catch (NSException* excp)
		{
			[m_protoObject release];
			m_protoObject = nil;

			[[layer undoManager] enableUndoRegistration];

			@throw;
		}
	}

	// return the partcode for the new object, so that we get it passed back in subsequent calls

	return mPartcode;
}

/** @brief Handle the mouse dragged event

 Keep dragging out the object
 @param p the local point where the mouse has been dragged to
 @param partCode the partcode returned by the mouseDown method
 @param layer the layer in which the tool is being applied
 @param event the original event
 @param aDel an optional delegate
 */

- (void)mouseDraggedToPoint:(NSPoint)p partCode:(NSInteger)pc layer:(DKLayer*)layer event:(NSEvent*)event delegate:(id)aDel {
    BOOL extended = (([event modifierFlags] & NSShiftKeyMask) != 0);
    DKObjectDrawingLayer* odl = (DKObjectDrawingLayer*)layer;
    NSArray* sel;
    DKDrawableObject* obj;
    @autoreleasepool {
        
        // the mouse has actually been dragged, so flag that
        
        mMouseMoved = YES;
        mLastPoint = p;
        
        // depending on the mode, carry out the operation for a mousedragged event
        @try
        {
            switch ([self operationMode]) {
                case kDKEditToolInvalidMode:
                case kDKEditToolSelectionMode:
                default:
                    if (m_protoObject != nil && !mDidPickup) {
                        [m_protoObject mouseDraggedAtPoint:p
                                                    inPart:pc
                                                     event:event];
                        
                        mLastPoint = p;
                    }
                    
                    [odl deselectAll];
                    
                    return;
                    
                    break;
                    
                case kDKEditToolMoveObjectsMode:
                    sel = [self draggedObjects];
                    
                    if ([sel count] > 0) {
                        [aDel toolWillPerformUndoableAction:self];
                        [self dragObjectsAsGroup:sel
                                         inLayer:odl
                                         toPoint:p
                                           event:event
                                       dragPhase:kDKDragMouseDragged];
                        mPerformedUndoableTask = YES;
                    }
                    break;
                    
                case kDKEditToolEditObjectMode:
                    obj = [odl singleSelection];
                    if (obj != nil) {
                        
                        
                        
                        
                        [aDel toolWillPerformUndoableAction:self];
                        [obj mouseDraggedAtPoint:p
                                          inPart:pc
                                           event:event];
                        mPerformedUndoableTask = YES;
                    }
                    break;
            }
        }
        @catch (NSException* exception)
        {
            NSLog(@"#### exception while dragging with selection tool: mode = %ld, exc = (%@) - ignored ####", (long)[self operationMode], exception);
        }
        
    }
}

/** @brief Handle the mouse up event

 This finalises he object creation by calling the -objectIsValid method. Valid means that the path
 is not empty or zero-sized for example. If the object is valid it is committed to the layer after
 re-enabling undo. Invalid objects are simply discarded. The delegate is called to signal an undoable
 task is about to be made.
 @param p the local point where the mouse went up
 @param partCode the partcode returned by the mouseDown method
 @param layer the layer in which the tool is being applied
 @param event the original event
 @param aDel an optional delegate
 @return YES if the tool did something undoable, NO otherwise
 */
- (BOOL)mouseUpAtPoint:(NSPoint)p partCode:(NSInteger)pc layer:(DKLayer*)layer event:(NSEvent*)event delegate:(id)aDel
{
#pragma unused(pc)
	NSAssert(layer != nil, @"layer was nil in creation tool mouse up");

	if (mDidPickup) {
		mDidPickup = NO;
		return NO;
	}
    
    DKObjectDrawingLayer* odl = (DKObjectDrawingLayer*)layer;
    mLastPoint = p;
    
    return [self finishUsingToolInLayer:odl
                               delegate:aDel
                                  event:event];


}

- (BOOL)isValidTargetLayer:(DKLayer*)aLayer
{
	return [aLayer isKindOfClass:[DKObjectDrawingLayer class]] && ![aLayer locked] && [aLayer visible];
}

#pragma mark - Snappy Edit on click

typedef struct {
    NSPoint p;
    NSEvent* event;
    BOOL multiDrag;
} _dragInfo;

static void dragFunction_mouseDown(const void* obj, void* context) {
    _dragInfo* dragInfo = (_dragInfo*)context;
    BOOL saveSnap = NO, saveShowsInfo = NO;
    
    if (dragInfo->multiDrag) {
        saveSnap = [(DKDrawableObject*)obj mouseSnappingEnabled];
        [(DKDrawableObject*)obj setMouseSnappingEnabled:NO];
        
        saveShowsInfo = [[(DKDrawableObject*)obj class] displaysSizeInfoWhenDragging];
        [[(DKDrawableObject*)obj class] setDisplaysSizeInfoWhenDragging:NO];
    }
    
    [(DKDrawableObject*)obj mouseDownAtPoint:dragInfo->p
                                      inPart:kDKDrawingEntireObjectPart
                                       event:dragInfo->event];
    
    if (dragInfo->multiDrag) {
        [(DKDrawableObject*)obj setMouseSnappingEnabled:saveSnap];
        [[(DKDrawableObject*)obj class] setDisplaysSizeInfoWhenDragging:saveShowsInfo];
    }
}

static void dragFunction_mouseDrag(const void* obj, void* context) {
    _dragInfo* dragInfo = (_dragInfo*)context;
    BOOL saveSnap = NO, saveShowsInfo = NO;
    
    if (dragInfo->multiDrag) {
        saveSnap = [(DKDrawableObject*)obj mouseSnappingEnabled];
        [(DKDrawableObject*)obj setMouseSnappingEnabled:NO];
        
        saveShowsInfo = [[(DKDrawableObject*)obj class] displaysSizeInfoWhenDragging];
        [[(DKDrawableObject*)obj class] setDisplaysSizeInfoWhenDragging:NO];
    }
    
    [(DKDrawableObject*)obj mouseDraggedAtPoint:dragInfo->p
                                         inPart:kDKDrawingEntireObjectPart
                                          event:dragInfo->event];
    if (dragInfo->multiDrag) {
        [(DKDrawableObject*)obj setMouseSnappingEnabled:saveSnap];
        [[(DKDrawableObject*)obj class] setDisplaysSizeInfoWhenDragging:saveShowsInfo];
    }
}

static void dragFunction_mouseUp(const void* obj, void* context) {
    _dragInfo* dragInfo = (_dragInfo*)context;
    
    BOOL saveSnap = NO, saveShowsInfo = NO;
    
    if (dragInfo->multiDrag) {
        saveSnap = [(DKDrawableObject*)obj mouseSnappingEnabled];
        [(DKDrawableObject*)obj setMouseSnappingEnabled:NO];
        
        saveShowsInfo = [[(DKDrawableObject*)obj class] displaysSizeInfoWhenDragging];
        [[(DKDrawableObject*)obj class] setDisplaysSizeInfoWhenDragging:NO];
    }
    
    [(DKDrawableObject*)obj mouseUpAtPoint:dragInfo->p
                                    inPart:kDKDrawingEntireObjectPart
                                     event:dragInfo->event];
    [(DKDrawableObject*)obj notifyVisualChange];
    
    if (dragInfo->multiDrag) {
        [(DKDrawableObject*)obj setMouseSnappingEnabled:saveSnap];
        [[(DKDrawableObject*)obj class] setDisplaysSizeInfoWhenDragging:saveShowsInfo];
    }
}

- (BOOL)finishUsingToolInLayer:(DKObjectDrawingLayer*)odl delegate:(id)aDel event:(NSEvent*)event {
    NSArray* sel = nil;
    DKDrawableObject* obj;
    NSDictionary* userInfoDict = [NSDictionary dictionaryWithObjectsAndKeys:odl, kDKSelectionToolTargetLayer, [odl singleSelection], kDKSelectionToolTargetObject, nil];
    BOOL extended = (([event modifierFlags] & NSShiftKeyMask) != 0);
    
    switch ([self operationMode]) {
        case kDKEditToolInvalidMode:
        case kDKEditToolSelectionMode:
        default:
            
//            BOOL controlKey = ([event modifierFlags] & NSControlKeyMask) != 0;
//            p = [[layer drawing] snapToGrid:p
//                            withControlFlag:controlKey];
            
            [self setDraggedObjects:nil];
            return [self finishCreation:aDel];
            
            break;
            
        case kDKEditToolMoveObjectsMode:
            sel = [self draggedObjects];
            
            if ([sel count] > 0) {
                [self dragObjectsAsGroup:sel
                                 inLayer:odl
                                 toPoint:mLastPoint
                                   event:event
                               dragPhase:kDKDragMouseUp];
                
                // directly inform the layer that the drag finished and how far the objects were moved
                
                if ([odl respondsToSelector:@selector(objects:
                                                      wereDraggedFromPoint:
                                                      toPoint:)])
                    [odl objects:sel
            wereDraggedFromPoint:mAnchorPoint
                         toPoint:mLastPoint];
            }
            
            [[NSNotificationCenter defaultCenter] postNotificationName:kDKSelectionToolDidFinishMovingObjects
                                                                object:self
                                                              userInfo:userInfoDict];
            break;
            
        case kDKEditToolEditObjectMode:
            obj = [odl singleSelection];
            [obj mouseUpAtPoint:mLastPoint
                         inPart:mPartcode
                          event:event];
            [[NSNotificationCenter defaultCenter] postNotificationName:kDKSelectionToolDidFinishEditingObject
                                                                object:self
                                                              userInfo:userInfoDict];
            break;
    }
    [self setDraggedObjects:nil];
    return mPerformedUndoableTask;
}

/** @brief Returns the tool's current operation mode
 @return the current operation mode */
- (DKEditToolOperation)operationMode
{
    return mOperationMode;
}

/** @brief Sets the tool's operation mode
 
 This is typically called automatically by the mouseDown method according to the context of the
 initial click.
 @param op the mode to enter */
- (void)setOperationMode:(DKEditToolOperation)op {
    mOperationMode = op;
//    NSLog(@"select tool set op mode = %d", op);
    LogEvent_(kInfoEvent, @"select tool set op mode = %d", op);
}


/** @brief Store a string representing an undoable action
 
 The string is simply stored until requested by the caller, it does not at this stage set the
 undo manager's action name.
 @param action a string
 */
- (void)setUndoAction:(NSString*)action {
//    [action retain];
//    [mUndoAction release];
//    mUndoAction = action;
}

- (void)setDraggedObjects:(NSArray*)objects {
    [objects retain];
    [mDraggedObjects release];
    mDraggedObjects = objects;
}

- (NSArray*)draggedObjects {
    return mDraggedObjects;
}

/** @brief Handle the drag of objects, either singly or multiply
 
 This drags one or more objects to the point <p>. It also is where the current state of the options
 for hiding the selection and allowing multiple drags is implemented. The method also deals with
 snapping during the drag - what happens is slightly different when one object is dragged as opposed
 to several objects - in the latter case the relative spatial positions of the objects is fixed
 rather than allowing each one to snap individually to the grid which is poor from a usability POV.
 This also tests the drag against the layer's current "exclusion rect". If the drag leaves this rect,
 a Drag Manager drag is invoked to allow the objects to be dragged to another document, layer or
 application.
 @param objects a list of objects to drag (may have only one item)
 @param layer the layer in which the objects exist
 @param p the current local point where the drag is
 @param event the event
 @param ph the drag phase - mouse down, dragged or up.
 */
- (void)dragObjectsAsGroup:(NSArray*)objects inLayer:(DKObjectDrawingLayer*)layer toPoint:(NSPoint)p event:(NSEvent*)event dragPhase:(DKEditToolDragPhase)ph
{
    NSAssert(objects != nil, @"attempt to drag with nil array");
    NSAssert([objects count] > 0, @"attempt to drag with empty array");
    
    [layer setRulerMarkerUpdatesEnabled:NO];
    
    // if set to hide the selection highlight during a drag, test that here and set the highlight visible
    // as required on the initial mouse down
    
    if ([self selectionShouldHideDuringDrag] && ph == kDKDragMouseDragged)
        [layer setSelectionVisible:NO];
    
    // if the mouse has left the layer's drag exclusion rect, this starts a drag of the objects as a "real" drag. Test for that here
    // and initiate the drag if needed. The drag will keep control until the items are dropped.
    
    if (ph == kDKDragMouseDragged) {
        NSRect der = [layer dragExclusionRect];
        if (!NSPointInRect(p, der)) {
            [layer beginDragOfSelectedObjectsWithEvent:event
                                                inView:[layer currentView]];
            if ([self selectionShouldHideDuringDrag])
                [layer setSelectionVisible:YES];
            
            // the drag will have clobbered the mouse up, but we need to post one to ensure that the sequence is correctly terminated.
            // this is particularly important for managing undo groups, which are exceedingly finicky.
            
            NSWindow* window = [event window];
            
            NSEvent* fakeMouseUp = [NSEvent mouseEventWithType:NSLeftMouseUp
                                                      location:[event locationInWindow]
                                                 modifierFlags:0
                                                     timestamp:[NSDate timeIntervalSinceReferenceDate]
                                                  windowNumber:[window windowNumber]
                                                       context:[NSGraphicsContext currentContext]
                                                   eventNumber:0
                                                    clickCount:1
                                                      pressure:0.0];
            
            [window postEvent:fakeMouseUp
                      atStart:YES];
            
            //NSLog(@"returning from drag source operation, phase = %d", ph);
            return;
        }
    }
    
    BOOL multipleObjects = [objects count] > 1;
//    BOOL controlKey = ([event modifierFlags] & NSControlKeyMask) != 0;
    
    // when moved as a group, individual mouse snapping is supressed - instead we snap the input point to the grid and
    // apply it to all - as usual control key can disable (or enable) snapping temporarily
    
//    if (multipleObjects) {
//        p = [[layer drawing] snapToGrid:p
//                        withControlFlag:controlKey];
//        
//        DKUndoManager* um = (DKUndoManager*)[layer undoManager];
//        
//        // set the undo manager to coalesce ABABABAB > AB instead of ABBBBBA > ABA
//        
//        if ([um respondsToSelector:@selector(setCoalescingKind:)]) {
//            if (ph == kDKDragMouseDown)
//                [um setCoalescingKind:kGCCoalesceAllMatchingTasks];
//            else if (ph == kDKDragMouseUp)
//                [um setCoalescingKind:kGCCoalesceLastTask];
//        }
//    }
    
    // if we have exceeded a non-zero proxy threshold, handle things using the proxy drag method instead.
    
    if ([self proxyDragThreshold] > 0 && [objects count] >= [self proxyDragThreshold]) {
        [self proxyDragObjectsAsGroup:objects
                              inLayer:layer
                              toPoint:p
                                event:event
                            dragPhase:ph];
    } else {
        
        _dragInfo dragInfo;
        
        dragInfo.p = p;
        dragInfo.event = event;
        dragInfo.multiDrag = multipleObjects;
        
        switch (ph) {
            case kDKDragMouseDown:
                CFArrayApplyFunction((CFArrayRef)objects, CFRangeMake(0, [objects count]), dragFunction_mouseDown, &dragInfo);
                break;
                
            case kDKDragMouseDragged:
                CFArrayApplyFunction((CFArrayRef)objects, CFRangeMake(0, [objects count]), dragFunction_mouseDrag, &dragInfo);
                break;
                
            case kDKDragMouseUp:
                CFArrayApplyFunction((CFArrayRef)objects, CFRangeMake(0, [objects count]), dragFunction_mouseUp, &dragInfo);
                break;
                
            default:
                break;
        }
        
        NSEnumerator* iter = [objects objectEnumerator];
        DKDrawableObject* o;
        BOOL saveSnap = NO;
        BOOL saveShowsInfo = NO;
        
        while ((o = [iter nextObject])) {
            if (multipleObjects) {
                saveSnap = [o mouseSnappingEnabled];
                [o setMouseSnappingEnabled:NO];
                
                saveShowsInfo = [[o class] displaysSizeInfoWhenDragging];
                [[o class] setDisplaysSizeInfoWhenDragging:NO];
            }
            
            switch (ph) {
                case kDKDragMouseDown:
                    [o mouseDownAtPoint:p
                                 inPart:kDKDrawingEntireObjectPart
                                  event:event];
                    [o notifyVisualChange];
                    break;
                    
                case kDKDragMouseDragged:
                    [o mouseDraggedAtPoint:p
                                    inPart:kDKDrawingEntireObjectPart
                                     event:event];
                    break;
                    
                case kDKDragMouseUp:
                    [o mouseUpAtPoint:p
                               inPart:kDKDrawingEntireObjectPart
                                event:event];
                    [o notifyVisualChange];
                    break;
                    
                default:
                    break;
            }
            
            if (multipleObjects) {
                [o setMouseSnappingEnabled:saveSnap];
                [[o class] setDisplaysSizeInfoWhenDragging:saveShowsInfo];
            }
        }
    }
    
    // set the undo action to say what we just did for a drag:
    
    if (ph == kDKDragMouseDragged) {
        if (multipleObjects) {
//            if (mDidCopyDragObjects)
//                [self setUndoAction:NSLocalizedString(@"Copy And Move Objects", @"undo string for copy and move (plural)")];
//            else
                [self setUndoAction:NSLocalizedString(@"Move Multiple Objects", @"undo string for move multiple objects")];
        } else {
//            if (mDidCopyDragObjects)
//                [self setUndoAction:NSLocalizedString(@"Copy And Move Object", @"undo string for copy and move (singular)")];
//            else
                [self setUndoAction:NSLocalizedString(@"Move Object", @"undo string for move single object")];
        }
    }
    
    // if the mouse wasn't dragged, select the single object if shift or command isn't down - this avoids the need to deselect all
    // before selecting a single object in an already selected group. By also testing mouse moved, the tool is smart
    // enough not to do this if it was an object drag that was done. Result for the user - intuitively thought-free behaviour. ;-)
    
    if (!mMouseMoved && ph == kDKDragMouseUp) {
        BOOL shift = ([event modifierFlags] & NSShiftKeyMask) != 0;
        BOOL cmd = ([event modifierFlags] & NSCommandKeyMask) != 0;
        
        if (!shift && !cmd) {
            DKDrawableObject* single = [layer hitTest:p];
            
            if (single != nil)
                [layer replaceSelectionWithObject:single];
        }
    }
    
    // on mouse up restore the selection visibility if required
    
    if ([self selectionShouldHideDuringDrag] && ph == kDKDragMouseUp)
        [layer setSelectionVisible:YES];
    
    [layer setRulerMarkerUpdatesEnabled:YES];
    [layer updateRulerMarkersForRect:[layer selectionLogicalBounds]];
}

/** @brief Should the selection highlight of objects should be supressed during a drag?
 
 The default is YES. Hiding the selection can make positioning objects by eye more precise.
 @return YES to hide selections during a drag, NO to leave them visible */
- (BOOL)selectionShouldHideDuringDrag {
    return NO;
}

- (void)proxyDragObjectsAsGroup:(NSArray*)objects inLayer:(DKObjectDrawingLayer*)layer toPoint:(NSPoint)p event:(NSEvent*)event dragPhase:(DKEditToolDragPhase)ph
{
#pragma unused(event)
    
    static NSSize offset;
    static NSPoint anchor;
    
    switch (ph) {
        case kDKDragMouseDown: {
            if (mProxyDragImage == nil) {
                mProxyDragImage = [[self prepareDragImage:objects
                                                  inLayer:layer] retain];
                
                offset.width = p.x - NSMinX([layer selectionBounds]);
                offset.height = p.y - NSMinY([layer selectionBounds]);
                anchor = p;
                
                mProxyDragDestRect.size = [mProxyDragImage size];
                mProxyDragDestRect.origin.x = p.x - offset.width;
                mProxyDragDestRect.origin.y = p.y - offset.height;
                
                [layer setNeedsDisplayInRect:mProxyDragDestRect];
                
                // need to hide the real objects being dragged. Since we cache the dragged list
                // locally we can do this without getting bad results from [layer selectedAvailableObjects]
                
                // we also want to keep the undo manager out of this:
                
                [[layer undoManager] disableUndoRegistration];
                
                NSEnumerator* iter = [objects objectEnumerator];
                DKDrawableObject* obj;
                
                while ((obj = [iter nextObject]))
                    [obj setVisible:NO];
                
                [[layer undoManager] enableUndoRegistration];
            }
            mInProxyDrag = YES;
        } break;
            
        case kDKDragMouseDragged: {
            [layer setNeedsDisplayInRect:mProxyDragDestRect];
            
            mProxyDragDestRect.size = [mProxyDragImage size];
            mProxyDragDestRect.origin.x = p.x - offset.width;
            mProxyDragDestRect.origin.y = p.y - offset.height;
            
            [layer setNeedsDisplayInRect:mProxyDragDestRect];
        } break;
            
        case kDKDragMouseUp: {
            [mProxyDragImage release];
            mProxyDragImage = nil;
            [layer setNeedsDisplayInRect:mProxyDragDestRect];
            
            // move the objects by the total drag distance
            
            CGFloat dx, dy;
            
            dx = p.x - anchor.x;
            dy = p.y - anchor.y;
            
            NSEnumerator* iter = [objects objectEnumerator];
            DKDrawableObject* obj;
            
            while ((obj = [iter nextObject])) {
                [obj offsetLocationByX:dx
                                   byY:dy];
                
                [[layer undoManager] disableUndoRegistration];
                [obj setVisible:YES];
                [[layer undoManager] enableUndoRegistration];
            }
            mInProxyDrag = NO;
        } break;
            
        default:
            break;
    }
}


- (void)drawRect:(NSRect)aRect inView:(NSView*)aView
{
#pragma unused(aRect)
    
    if (mInProxyDrag && mProxyDragImage != nil) {
        // need to flip the image if needed
        
        SAVE_GRAPHICS_CONTEXT //[NSGraphicsContext saveGraphicsState];
        if ([aView isFlipped])
        {
            NSAffineTransform* unflipper = [NSAffineTransform transform];
            [unflipper translateXBy:mProxyDragDestRect.origin.x
                                yBy:mProxyDragDestRect.origin.y + mProxyDragDestRect.size.height];
            [unflipper scaleXBy:1.0
                            yBy:-1.0];
            [unflipper concat];
        }
        
        // for slightly higher performance but less visual fidelity, comment this out:
        
        [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
        
        // the drag image is drawn at 80% opacity to help with the "interleaving" issue. In practice this works pretty well.
        
        [mProxyDragImage drawAtPoint:NSZeroPoint
                            fromRect:NSZeroRect
                           operation:NSCompositeSourceAtop
                            fraction:0.8];
        
        RESTORE_GRAPHICS_CONTEXT //[NSGraphicsContext restoreGraphicsState];
    }
}

/*
The default method creates the image by asking the layer to make one using its standard imaging
methods. You can override this for different approaches. Typically the drag image has the bounds of
the selected objects - the caller will position the image based on that assumption. This is only
invoked if the proxy drag threshold was exceeded and not zero.
@param objectsToDrag the list of objects that will be dragged
@param layer the layer they are owned by
@return an image, representing the dragged objects.
*/
- (NSImage*)prepareDragImage:(NSArray*)objectsToDrag inLayer:(DKObjectDrawingLayer*)layer
{
#pragma unused(objectsToDrag)
    
    NSImage* img = [layer imageOfSelectedObjects];
    
    // draw a dotted line around the boundary.
    
#if SHOW_DRAG_PROXY_BOUNDARY
    NSRect br = NSZeroRect;
    br.size = [img size];
    br = NSInsetRect(br, 1, 1);
    NSBezierPath* bp = [NSBezierPath bezierPathWithRect:br];
    CGFloat pattern[] = { 4, 4 };
    
    [bp setLineWidth:1.0];
    [bp setLineDash:pattern
              count:2
              phase:0];
    
    [img lockFocus];
    [[NSColor grayColor] set];
    [bp stroke];
    [img unlockFocus];
#endif
    
    return img;
}

/** @brief Sets the number of selected objects at which a proxy drag is used rather than a live drag
 
 Dragging large numbers of objects can be unacceptably slow due to the very high numbers of view updates
 it entails. By setting a threshold, this tool can use a much faster (but less realistic) drag using
 a temporary image of the objects being dragged. A value of 0 will disable proxy dragging. Note that
 this gives a hugh performance gain for large numbers of objects - in fact it makes dragging of a lot
 of objects actually feasible. The default threshold is 50 objects. Setting this to 1 effectively
 makes proxy dragging operate at all times.
 @param numberOfObjects the number above which a proxy drag is used
 */
- (void)setProxyDragThreshold:(NSUInteger)numberOfObjects {
    mProxyDragThreshold = numberOfObjects;
}

/** @brief The number of selected objects at which a proxy drag is used rather than a live drag
 
 Dragging large numbers of objects can be unacceptably slow due to the very high numbers of view updates
 it entails. By setting a threshold, this tool can use a much faster (but less realistic) drag using
 a temporary image of the objects being dragged. A value of 0 will disable proxy dragging.
 @return the number above which a proxy drag is used
 */
- (NSUInteger)proxyDragThreshold {
    return mProxyDragThreshold;
}

- (void)changeSelectionWithTarget:(DKDrawableObject*)targ inLayer:(DKObjectDrawingLayer*)layer event:(NSEvent*)event
{
    // given an object that we know was generally hit, this changes the selection. What happens can also depend on modifier keys, but the
    // result is that the layer's selection represents what a subsequent selection drag will consist of.
    
    BOOL extended = NO; //(([event modifierFlags] & NSShiftKeyMask) != 0 );
    BOOL invert = NO;// (([event modifierFlags] & NSCommandKeyMask) != 0) || (([event modifierFlags] & NSShiftKeyMask) != 0);
    BOOL isSelected = [layer isSelectedObject:targ];
    
    // if already selected and we are not inverting, nothing to do if multi-drag is ON
    
    NSString* an = NSLocalizedString(@"Change Selection", @"undo string for change selecton");
    
    if (extended) {
        [layer addObjectToSelection:targ];
        an = NSLocalizedString(@"Add To Selection", @"undo string for add selection");
    } else {
        if (invert) {
            if (isSelected) {
                [layer removeObjectFromSelection:targ];
                an = NSLocalizedString(@"Remove From Selection", @"undo string for remove selection");
            } else {
                [layer addObjectToSelection:targ];
                an = NSLocalizedString(@"Add To Selection", @"undo string for add selection");
            }
        } else
            [layer replaceSelectionWithObject:targ];
    }
    
    if ([layer selectionChangesAreUndoable]) {
        [self setUndoAction:an];
        mPerformedUndoableTask = YES;
    }
}

@end

/**
 @author Contributions from the community; see CONTRIBUTORS.md
 @date 2005-2016
 @copyright MPL2; see LICENSE.txt
*/

#import "NSMutableArray+DKAdditions.h"

@implementation NSMutableArray (DKAdditions)

/**  */
- (void)addUniqueObjectsFromArray:(NSArray*)array
{
	// adds objects from <array> to the receiver, but only those not already contained by it

	NSEnumerator* iter = [array objectEnumerator];
	id obj;

	while ((obj = [iter nextObject])) {
		if (![self containsObject:obj])
			[self addObject:obj];
	}
}

@end

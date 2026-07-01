#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MDBlockKind) { MDBlockKindEqual, MDBlockKindChanged };
typedef NS_ENUM(NSInteger, MDPickSide) { MDPickSideUnpicked, MDPickSideLeft, MDPickSideRight, MDPickSideManual };

@interface MDBlock : NSObject
@property MDBlockKind kind;
@property (copy) NSArray<NSString *> *leftLines;
@property (copy) NSArray<NSString *> *rightLines;
@property (copy) NSArray<NSString *> *manualLines;
@property NSInteger leftStartLine;
@property NSInteger rightStartLine;
@property MDPickSide pick;
@end

@interface MDDocument : NSObject
@property (copy) NSArray<MDBlock *> *blocks;
- (BOOL)canSave;
- (NSString *)mergedText:(NSError **)error;
@end

#ifdef __cplusplus
extern "C" {
#endif
void MDSetLogDirectory(NSString *directoryPath);
MDDocument *MDMakeDiff(NSString *leftText, NSString *rightText, NSError **error);
#ifdef __cplusplus
}
#endif

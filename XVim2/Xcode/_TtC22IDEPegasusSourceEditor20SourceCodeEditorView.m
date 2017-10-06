//
//  _TtC22IDEPegasusSourceEditor20SourceCodeEditorView.m
//  XVim2
//
//  Created by Shuichiro Suzuki on 8/27/17.
//  Copyright © 2017 Shuichiro Suzuki. All rights reserved.
//

#import "_TtC22IDEPegasusSourceEditor20SourceCodeEditorView.h"
#import "NSObject+Swizzle.h"
#import "XVimKeyStroke.h"
#import "SourceEditorViewProxy.h"
#import "Logger.h"
#import "XVimCmdArg.h"
#import <QuartzCore/QuartzCore.h>
#import "NSObject+ExtraData.h"

#define CONST_STR(_name) NSString *_name = @#_name ;

CONST_STR(EDLastEvent);
CONST_STR(EDMode);
CONST_STR(EDProxy);

@implementation _TtC22IDEPegasusSourceEditor20SourceCodeEditorView(XVim)
+ (void)xvim_hook{
    [self xvim_swizzleInstanceMethod:@selector(keyDown:) with:@selector(xvim_keyDown:)];
}

-(SourceEditorViewProxy*)proxy {
    SourceEditorViewProxy *p = [self extraDataForName:EDProxy];
    if (p == nil || (NSNull*)p == NSNull.null) {
        p = [[SourceEditorViewProxy alloc] initWithSourceEditorView:self];
        [self setExtraData:p forName:EDProxy];
    }
    return p;
}

-(void)xvim_setupOnFirstAppearance
{
    self.xvim_mode = XVIM_MODE_NORMAL;
}

-(XVimMode)xvim_mode {
    return [self integerForName:EDMode];
}

-(void)setXvim_mode:(XVimMode)xvim_mode {
    [self setInteger:xvim_mode forName:EDMode];
    if (xvim_mode == XVIM_MODE_INSERT) {
        self.proxy.cursorStyle = CursorStyleVerticalBar;
    }
    else {
        self.proxy.cursorStyle = CursorStyleBlock;
    }
}

- (NSMutableArray*)xvim_key_queue{
    NSMutableArray* obj;
    if( nil == (obj = [self extraDataForName:@"xvim_key_queue"]) ){
        obj = [NSMutableArray new];
        [self setExtraData:obj forName:@"xvim_key_queue"];
    }
    return obj;
}
- (CALayer*)xvim_cmd_layer{
    for (CALayer *layer in [self.layer sublayers]) {
        if ([[layer name] isEqualToString:@"xvim_cmd_layer"]) {
            return layer;
        }
    }
    CATextLayer* textLayer = [[CATextLayer alloc] init];
    [textLayer setName:@"xvim_cmd_layer"];
    [self.layer addSublayer:textLayer];

    return textLayer;
}

- (void)xvim_keyDown:(NSEvent*)event{
    [self.xvim_key_queue addObject:[event toXVimKeyStroke]];
    [self xvim_handleKeys:[XVimCmdArg new]];
    [self xvim_updateCommandLine:[XVimCmdArg new]];
}

- (XVimKeyStroke*)xvim_nextKey:(XVimCmdArg*)arg{
    [self xvim_updateCommandLine:arg];
    XVimKeyStroke* stroke=nil;
    if( 0 != [self.xvim_key_queue count]){
        stroke = [self.xvim_key_queue objectAtIndex:0];
        [self.xvim_key_queue removeObjectAtIndex:0];
    }else{
        NSEvent *event = [self.window nextEventMatchingMask:NSEventMaskKeyDown];
        [self.window discardEventsMatchingMask:NSEventMaskAny beforeEvent:event];
        stroke = [event toXVimKeyStroke];
    }
    [arg.args appendString:[stroke keyNotation]];
    return stroke;
}

- (void)xvim_insert:(XVimCmdArg*)arg{
    self.xvim_mode = XVIM_MODE_INSERT;
    while(true){
        XVimKeyStroke *stroke =  [self xvim_nextKey:arg];
        switch(stroke.keycode){
            case u'\x1b': //ESC
                self.xvim_mode = XVIM_MODE_NORMAL;
                return;
            case XVimMakeKeyCode(XVIM_MOD_CTRL,  u'n'):
                [self nextCompletion:self];
                break;
            case XVimMakeKeyCode(XVIM_MOD_CTRL,  u'p'):
                [self previousCompletion:self];
                return;
        }
        [self xvim_keyDown:[stroke toEvent]];
    }
}

- (void)xvim_delete:(XVimCmdArg*)arg{
     XVimKeyStroke *stroke =  [self xvim_nextKey:arg];
    switch(stroke.keycode){
        // For simple ascii you can just use char here instad of XVimMakeKeyCode(0, u'x')
        case 'd':
            [self moveToBeginningOfLine:self];
            [self deleteToEndOfLine:self];
            [self deleteBackward:self];
            break;
        case 'w':
            [self deleteWordForward:self];
    }
    return;
}

- (void)xvim_key_g:(XVimCmdArg*)arg {
    XVimKeyStroke* stroke = [self xvim_nextKey:arg];
    switch (stroke.keycode) {
        case 'g':
            [self moveToBeginningOfDocument:self];
            break;
    }
    return;
}

- (void) xvim_comma_command:(XVimCmdArg*)arg {
    XVimKeyStroke* stroke = [self xvim_nextKey:arg];
    switch (stroke.keycode) {
        case 'w':
            [NSApp sendAction:@selector(ide_saveDocument:) to:nil from:self];
            break;
    }
    return;
}

- (void)xvim_visual:(XVimCmdArg*)arg{
    while(true){
        XVimKeyStroke *stroke =  [self xvim_nextKey:arg];
        switch(stroke.keycode){
                // For simple ascii you can just use char here instad of XVimMakeKeyCode(0, u'x')
            case u'\x1b': //ESC
                return;
            case 'd':
                [self delete:self];
                return;
            case 'w':
                [self moveWordRightAndModifySelection:self];
                break;
            case 'j':
                [self moveDownAndModifySelection:self];
                break;
            case 'k':
                [self moveUpAndModifySelection:self];
                break;
            case 'h':
                [self moveLeftAndModifySelection:self];
                break;
            case 'l':
                [self moveRightAndModifySelection:self];
                break;
            case '$':
                [self moveToEndOfLineAndModifySelection:self];
                break;
            case '0':
                [self moveToBeginningOfLineAndModifySelection:self];
                break;
            case 'y':
                [self copy:self];
                break;
            case 'x':
                [self copy:self];
                [self delete:self];
                break;
        }
    }
    return;
}

// Normal mode event handling
- (void)xvim_handleKeys:(XVimCmdArg*)arg{
    self.xvim_mode = XVIM_MODE_NORMAL;
    // Handle event which can be handled by this
    XVimKeyStroke *stroke =  [self xvim_nextKey:arg];

    switch(stroke.keycode){
        // For simple ascii you can just use char here instad of XVimMakeKeyCode(0, u'x')
        case 'a':
            [self xvim_insert:arg];
            [self moveRight:self];
            break;
        case 'b':
            [self moveWordBackward:self];
            break;
        case 'd':
            [self xvim_delete:arg];
            break;
        case 'w':
            [self moveWordRight:self];
            break;
        case 'i':
            [self xvim_insert:arg];
            break;
        case 'j':
            [self moveDown:self];
            break;
        case 'k':
            [self moveUp:self];
            break;
        case 'h':
            [self moveLeft:self];
            break;
        case 'l':
            [self moveRight:self];
            break;
        case '$':
            [self moveToEndOfLine:self];
            break;
        case '0':
            [self moveToBeginningOfLine:self];
            break;
        case 'o':
            [self moveToEndOfLine:self];
            [self insertNewline:self];
            [self xvim_insert:arg];
            break;
        case 'p':
            [self paste:self];
            break;
        case 'D':
            [self deleteToEndOfLine:self];
            break;
        case 'g':
            [self xvim_key_g:arg];
            break;
        case 'G':
            [self moveToEndOfDocument:self];
            break;
        case 'u':
            [[self undoManager] undo];
            break;
        case 'v':
            [self xvim_visual:arg];
            break;
        case XVimMakeKeyCode(0, NSUpArrowFunctionKey):
            [self moveUp:self];
            break;
        case XVimMakeKeyCode(0, NSDownArrowFunctionKey):
            [self moveDown:self];
            break;
        case XVimMakeKeyCode(0, NSLeftArrowFunctionKey):
            [self moveLeft:self];
            break;
        case XVimMakeKeyCode(0, NSRightArrowFunctionKey):
            [self moveRight:self];
            break;
        case 'x':
            [self deleteForward:self];
            break;
        case ':':
            [self xvim_comma_command:arg];
            break;
    }
}

- (void)xvim_updateCommandLine:(XVimCmdArg*)arg{
    CATextLayer* cmd = (CATextLayer*)[self xvim_cmd_layer];
    if( arg.args.length == 0 ){
        [cmd setHidden:YES];
        return;
    }
    [cmd setHidden:NO];
    [cmd setString:arg.args];
    CGRect rect = self.frame;
    rect.origin.y = rect.size.height - 20;
    rect.size.height = 20;
    [cmd setFrame: rect];
    cmd.foregroundColor = [NSColor blackColor].CGColor;
    cmd.backgroundColor = [NSColor colorWithRed:0 green:0 blue:0 alpha:0.2].CGColor;
    cmd.fontSize = 16.0;
}
@end


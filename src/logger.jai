LogLevel :: enum {
    DEBUG;
    INFO;
    WARNING;
    ERROR;
    FATAL;
}


TaggedLogger :: struct($tag: string) {
    debug   :: #bake_arguments log_message(level = .DEBUG,   tag = tag);
    info    :: #bake_arguments log_message(level = .INFO,    tag = tag);
    warning :: #bake_arguments log_message(level = .WARNING, tag = tag);
    error   :: #bake_arguments log_message(level = .ERROR,   tag = tag);
    fatal   :: #bake_arguments log_message(level = .FATAL,   tag = tag);
}


log_message :: ($level: LogLevel, $tag: string, $format: string, args: ..Any) {
    prefix_fg,    prefix_bg    :: #run get_style_for_prefix   (level);
    separator_fg, separator_bg :: #run get_style_for_separator(level);
    message_fg,   message_bg   :: #run get_style_for_message  (level);

    prefix_style    :: #run String.join(as_foreground_color(prefix_fg),    as_background_color(prefix_bg));
    separator_style :: #run String.join(as_foreground_color(separator_fg), as_background_color(separator_bg));
    message_style   :: #run String.join(as_foreground_color(message_fg),   as_background_color(message_bg));

    separator       :: #run build_separator(level);
    empty_separator :: #run build_separator(level, keep_empty = true);
    prefix          :: #run String.join(message_style, "\n", prefix_style, build_prefix(tag),                    "  ", separator_style, separator,       message_style, "  ");
    empty_prefix    :: #run String.join(               "\n", prefix_style, build_prefix(tag, keep_empty = true), "  ", separator_style, empty_separator, message_style, "  ");

    message := Basic.sprint(format, ..args,, Basic.temp);
    lines   := String.split(message, cast(u8) #char "\n",, Basic.temp);

    preformatted_message := String.join(..lines, separator = empty_prefix,, Basic.temp);

    complete_message := String.join(prefix, preformatted_message, RESET,, Basic.temp);
    write_string(complete_message);
}


#scope_file


MAX_TAG_LENGTH        :: 16;
RESET                 :: "\e[0m";
MOVE_CURSOR_1_LINE_UP :: "\e[1A";


build_prefix :: ($tag: string, $keep_empty: bool = false) -> string {
    prefix := string.{data = Basic.alloc(MAX_TAG_LENGTH), count = MAX_TAG_LENGTH};

    for ix:0..prefix.count - 1 {
        prefix[ix] = #char " ";
    }
    #if !keep_empty {
        memcpy(prefix.data, tag.data, Basic.min(prefix.count, tag.count));
    }

    return prefix;
}

build_separator :: inline ($level: LogLevel, $keep_empty: bool = false) -> string {
    #if keep_empty {
        return "   ";
    } else #if #complete level == {
        case .DEBUG;   return " D ";
        case .INFO;    return " I ";
        case .WARNING; return " W ";
        case .ERROR;   return " E ";
        case .FATAL;   return " F ";
    }
}


get_style_for_prefix :: ($level: LogLevel) -> (foreground: PickedColor, background: PickedColor) {
    #if level == {
        case .FATAL;  return .BLACK, .WHITE;
        case;         return .WHITE, .RESET;
    }
}

get_style_for_separator :: ($level: LogLevel) -> (foreground: PickedColor, background: PickedColor) {
    #if #complete level == {
        case .DEBUG;   return .GREEN_BRIGHT, .GREEN;
        case .INFO;    return .WHITE,        .BLUE;
        case .WARNING; return .BLACK,        .YELLOW;
        case .ERROR;   return .WHITE,        .RED;
        case .FATAL;   return .WHITE,        .RESET;
    }
}

get_style_for_message :: ($level: LogLevel) -> (foreground: PickedColor, background: PickedColor) {
    #if #complete level == {
        case .DEBUG;   return .GREEN_DIMMED,  .BLACK_RESET;
        case .INFO;    return .WHITE,         .BLACK_RESET;
        case .WARNING; return .YELLOW_DIMMED, .BLACK_RESET;
        case .ERROR;   return .RED_DIMMED,    .BLACK_RESET;
        case .FATAL;   return .ORANGE,        .WHITE;
    }
}


PickedColor :: enum u64 {
    RESET       :: ~(cast(u64) 0);
    BLACK_RESET :: RESET;

    // BLACK  :: 0x1E1E24;  // Raisin black
    // WHITE  :: 0xF5FBEF;  // Ivory
    // BLUE   :: 0x1E91D6;  // Celestial blue
    // ORANGE :: 0xFF6B35;  // Orange (Crayola)

    BLACK         :: 0x090300;
    WHITE         :: 0xF5FBEF;
    YELLOW        :: 0xFDED02;
    YELLOW_DIMMED :: 0xFCBA04;  // Selective yellow
    RED           :: 0xDB2D20;
    RED_DIMMED    :: 0xD72218;  // Rojo
    GREEN         :: 0x01A252;
    GREEN_DIMMED  :: 0x21A179;  // Jungle green
    GREEN_BRIGHT  :: 0x9EFF6E;
    BLUE          :: 0x01A0E4;
    ORANGE        :: 0xFF6B35;
}

as_foreground_color :: ($color: PickedColor) -> string {
    #if color == {
        case .RESET; return "\e[39m";
        case; {
            r :: (color >> 16) & 0xFF;
            g :: (color >>  8) & 0xFF;
            b :: (color >>  0) & 0xFF;
            return Basic.sprint("\e[38;2;%;%;%m", r, g, b);
        }
    }
}

as_background_color :: ($color: PickedColor) -> string {
    #if color == {
        case .RESET; return "\e[49m";
        case; {
            r :: (color >> 16) & 0xFF;
            g :: (color >>  8) & 0xFF;
            b :: (color >>  0) & 0xFF;
            return Basic.sprint("\e[48;2;%;%;%m", r, g, b);
        }
    }
}


// Basic  :: #import "Basic";
// String :: #import "String";
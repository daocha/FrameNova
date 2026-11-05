import Foundation

struct LayerEffect:Equatable {
    var alpha = 1.0,dx = 0.0,dy = 0.0,scale = 1.0
}
enum TransitionEffects {
    static func upper(_ clips:[Clip],index:Int)->Bool {clips.prefix(index+1).dropFirst().filter {$0.transitionIn != nil}.count%2 == 0}
    static func dipAlpha(_ progress:Double)->Double {clamp(1-abs(2*progress-1),0,1)}
    static func effect(_ type:TransitionType,progress:Double,incoming:Bool,incomingOnTop:Bool)->LayerEffect {
        let q = clamp(progress,0,1),e = q*q*(3-2*q),top = incoming == incomingOnTop
        switch type {
        case .fade:return LayerEffect(alpha:top ? (incoming ? e:1-e):1)
        case .dipBlack,.dipWhite:return LayerEffect(alpha:incoming ? (q>=0.5 ? 1:0):(q<0.5 ? 1:0))
        case .pushLeft:return LayerEffect(dx:incoming ? 1-e : -e)
        case .pushRight:return LayerEffect(dx:incoming ? e-1:e)
        case .pushUp:return LayerEffect(dy:incoming ? 1-e : -e)
        case .pushDown:return LayerEffect(dy:incoming ? e-1:e)
        case .slideLeft:return LayerEffect(dx:top ? (incoming ? 1-e : -e):0)
        case .slideRight:return LayerEffect(dx:top ? (incoming ? e-1:e):0)
        case .slideUp:return LayerEffect(dy:top ? (incoming ? 1-e : -e):0)
        case .slideDown:return LayerEffect(dy:top ? (incoming ? e-1:e):0)
        case .zoomIn:return LayerEffect(alpha:top ? (incoming ? e:1-e):1,scale:incoming ? 0.6+0.4*e:1+0.6*e)
        case .zoomOut:return LayerEffect(alpha:top ? (incoming ? e:1-e):1,scale:incoming ? 1.6-0.6*e:1-0.4*e)
        }
    }
    static func at(_ track:Track,clipID:String,time:Int64)->LayerEffect {
        guard track.kind == .main,let i = track.clips.firstIndex(where:{$0.id == clipID}) else {return LayerEffect()}
        let clip = track.clips[i]
        if let transition = clip.transitionIn,i>0,time<clip.startUs+transition.durationUs {
            return effect(transition.type,progress:Double(time-clip.startUs)/Double(transition.durationUs),incoming:true,incomingOnTop:upper(track.clips,index:i))
        }
        if i+1<track.clips.count {
            let next = track.clips[i+1]
            if let transition = next.transitionIn,time>=next.startUs,time<next.startUs+transition.durationUs {
                return effect(transition.type,progress:Double(time-next.startUs)/Double(transition.durationUs),incoming:false,incomingOnTop:upper(track.clips,index:i+1))
            }
        }
        return LayerEffect()
    }
}
struct TextAnimationEffect:Equatable {
    var alpha = 1.0,dy = 0.0,scale = 1.0,visible = 1.0
}
enum TextAnimationMath {
    static func effect(_ animation:TextAnimation,progress:Double,entering:Bool)->TextAnimationEffect {
        let q = clamp(progress,0,1),e = 1-(1-q)*(1-q)
        switch animation {
        case .none:return TextAnimationEffect()
        case .fade:return TextAnimationEffect(alpha:e)
        case .slideUp:return TextAnimationEffect(alpha:e,dy:(1-e)*(entering ? 0.06 : -0.06))
        case .slideDown:return TextAnimationEffect(alpha:e,dy:(1-e)*(entering ? -0.06 : 0.06))
        case .pop:return TextAnimationEffect(alpha:min(1,q*2),scale:q<0.7 ? 0.5+0.6*(q/0.7):1.1-0.1*((q-0.7)/0.3))
        case .zoom:return TextAnimationEffect(alpha:e,scale:1.4-0.4*e)
        case .typewriter:return TextAnimationEffect(visible:q)
        }
    }
    static func at(_ style:TextStyle,local:Int64,duration:Int64)->TextAnimationEffect {
        let d = max(1,min(style.animDurationUs,duration/2))
        if style.animOut != .none,duration-local<d {return effect(style.animOut,progress:Double(duration-local)/Double(d),entering:false)}
        if style.animIn != .none,local<d {return effect(style.animIn,progress:Double(local)/Double(d),entering:true)}
        return TextAnimationEffect()
    }
}
